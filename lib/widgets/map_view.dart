import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart';
import '../services/offline_area_service.dart';
import '../services/simple_tile_service.dart';
import '../services/network_status.dart';
import '../models/osm_camera_node.dart';
import '../models/camera_profile.dart';
import '../models/tile_provider.dart';
import 'debouncer.dart';
import 'camera_provider_with_cache.dart';
import 'map/camera_markers.dart';
import 'map/direction_cones.dart';
import 'map/map_overlays.dart';
import 'network_status_indicator.dart';
import '../dev_config.dart';

class MapView extends StatefulWidget {
  final MapController controller;
  const MapView({
    super.key,
    required this.controller,
    required this.followMe,
    required this.onUserGesture,
  });

  final bool followMe;
  final VoidCallback onUserGesture;

  @override
  State<MapView> createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  late final MapController _controller;
  final Debouncer _cameraDebounce = Debouncer(kDebounceCameraRefresh);
  final Debouncer _tileDebounce = Debouncer(const Duration(milliseconds: 150));

  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;

  late final CameraProviderWithCache _cameraProvider;
  late final SimpleTileHttpClient _tileHttpClient;
  
  // Track profile changes to trigger camera refresh
  List<CameraProfile>? _lastEnabledProfiles;
  
  // Track zoom to clear queue on zoom changes
  double? _lastZoom;

  @override
  void initState() {
    super.initState();
    OfflineAreaService();
    _controller = widget.controller;
    _tileHttpClient = SimpleTileHttpClient();
    _initLocation();

    // Set up camera overlay caching
    _cameraProvider = CameraProviderWithCache.instance;
    _cameraProvider.addListener(_onCamerasUpdated);
    
    // Fetch initial cameras
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCamerasFromProvider();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _cameraDebounce.dispose();
    _tileDebounce.dispose();
    _cameraProvider.removeListener(_onCamerasUpdated);
    _tileHttpClient.close();
    super.dispose();
  }

  void _onCamerasUpdated() {
    if (mounted) setState(() {});
  }

  /// Public method to retry location initialization (e.g., after permission granted)
  void retryLocationInit() {
    debugPrint('[MapView] Retrying location initialization');
    _initLocation();
  }



  void _refreshCamerasFromProvider() {
    final appState = context.read<AppState>();
    LatLngBounds? bounds;
    try {
      bounds = _controller.camera.visibleBounds;
    } catch (_) {
      return;
    }
    final zoom = _controller.camera.zoom;
    if (zoom < kCameraMinZoomLevel) {
      // Show a snackbar-style bubble, if desired
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cameras not drawn below zoom level $kCameraMinZoomLevel'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _cameraProvider.fetchAndUpdate(
      bounds: bounds,
      profiles: appState.enabledProfiles,
      uploadMode: appState.uploadMode,
    );
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followMe && !oldWidget.followMe && _currentLatLng != null) {
      _controller.move(_currentLatLng!, _controller.camera.zoom);
    }
  }

  Future<void> _initLocation() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

    _positionSub =
        Geolocator.getPositionStream().listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() => _currentLatLng = latLng);
      if (widget.followMe) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              _controller.move(latLng, _controller.camera.zoom);
            } catch (e) {
              debugPrint('MapController not ready yet: $e');
            }
          }
        });
      }
    });
  }

  double _safeZoom() {
    try {
      return _controller.camera.zoom;
    } catch (_) {
      return 15.0;
    }
  }

  /// Helper to check if two profile lists are equal
  bool _profileListsEqual(List<CameraProfile> list1, List<CameraProfile> list2) {
    if (list1.length != list2.length) return false;
    // Compare by profile IDs since profiles are value objects
    final ids1 = list1.map((p) => p.id).toSet();
    final ids2 = list2.map((p) => p.id).toSet();
    return ids1.length == ids2.length && ids1.containsAll(ids2);
  }

  /// Build tile layer based on selected tile provider
  Widget _buildTileLayer(AppState appState) {
    final providerConfig = TileProviders.getByType(appState.tileProvider);
    if (providerConfig == null) {
      // Fallback to OSM if somehow we have an invalid provider
      return TileLayer(
        urlTemplate: TileProviders.osmStreet.urlTemplate,
        userAgentPackageName: 'com.stopflock.flock_map_app',
        tileProvider: NetworkTileProvider(
          httpClient: _tileHttpClient,
        ),
      );
    }

    // For OSM tiles, use our custom HTTP client for offline/online routing
    if (providerConfig.type == TileProviderType.osmStreet) {
      return TileLayer(
        urlTemplate: providerConfig.urlTemplate,
        userAgentPackageName: 'com.stopflock.flock_map_app',
        tileProvider: NetworkTileProvider(
          httpClient: _tileHttpClient,
        ),
      );
    }

    // For other providers, use standard HTTP client (no offline support yet)
    return TileLayer(
      urlTemplate: providerConfig.urlTemplate,
      userAgentPackageName: 'com.stopflock.flock_map_app',
      additionalOptions: {
        'attribution': providerConfig.attribution,
      },
    );
  }



  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.session;

    // Check if enabled profiles changed and refresh cameras if needed
    final currentEnabledProfiles = appState.enabledProfiles;
    if (_lastEnabledProfiles == null || 
        !_profileListsEqual(_lastEnabledProfiles!, currentEnabledProfiles)) {
      _lastEnabledProfiles = List.from(currentEnabledProfiles);
      // Refresh cameras when profiles change
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Force display refresh first (for immediate UI update)
        _cameraProvider.refreshDisplay();
        // Then fetch new cameras for newly enabled profiles
        _refreshCamerasFromProvider();
      });
    }

    // Seed add‑mode target once, after first controller center is available.
    if (session != null && session.target == null) {
      try {
        final center = _controller.camera.center;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => appState.updateSession(target: center),
        );
      } catch (_) {/* controller not ready yet */}
    }

    final zoom = _safeZoom();
    // Fetch cached cameras for current map bounds (using Consumer so overlays redraw instantly)
    Widget cameraLayers = Consumer<CameraProviderWithCache>(
      builder: (context, cameraProvider, child) {
        LatLngBounds? mapBounds;
        try {
          mapBounds = _controller.camera.visibleBounds;
        } catch (_) {
          mapBounds = null;
        }
        final cameras = (mapBounds != null)
            ? cameraProvider.getCachedCamerasForBounds(mapBounds)
            : <OsmCameraNode>[];
        
        final markers = CameraMarkersBuilder.buildCameraMarkers(
          cameras: cameras,
          mapController: _controller,
          userLocation: _currentLatLng,
        );

        final overlays = DirectionConesBuilder.buildDirectionCones(
          cameras: cameras,
          zoom: zoom,
          session: session,
        );

        return Stack(
          children: [
            PolygonLayer(polygons: overlays),
            MarkerLayer(markers: markers),
          ],
        );
      }
    );

    return Stack(
      children: [
        FlutterMap(
          key: ValueKey('map_offline_${appState.offlineMode}_provider_${appState.tileProvider.name}'),
          mapController: _controller,
          options: MapOptions(
            initialCenter: _currentLatLng ?? LatLng(37.7749, -122.4194),
            initialZoom: 15,
            maxZoom: 19,
            onPositionChanged: (pos, gesture) {
              setState(() {}); // Instant UI update for zoom, etc.
              if (gesture) widget.onUserGesture();
              if (session != null) {
                appState.updateSession(target: pos.center);
              }
              
              // Show waiting indicator when map moves (user is expecting new content)
              NetworkStatus.instance.setWaiting();
              
              // Only clear tile queue on significant ZOOM changes (not panning)
              final currentZoom = pos.zoom;
              final zoomChanged = _lastZoom != null && (currentZoom - _lastZoom!).abs() > 0.5;
              
              if (zoomChanged) {
                _tileDebounce(() {
                  debugPrint('[MapView] Zoom change detected - clearing stale tile requests');
                  _tileHttpClient.clearTileQueue();
                });
              }
              _lastZoom = currentZoom;
              
              // Request more cameras on any map movement/zoom at valid zoom level (slower debounce)
              if (pos.zoom >= 10) {
                _cameraDebounce(_refreshCamerasFromProvider);
              }
            },
          ),
          children: [
            _buildTileLayer(appState),
            cameraLayers,
            // Built-in scale bar from flutter_map 
            Scalebar(
              alignment: Alignment.bottomLeft,
              padding: EdgeInsets.only(left: 8, bottom: kScaleBarBottomOffset), // from dev_config
              textStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              lineColor: Colors.black,
              strokeWidth: 3,
              // backgroundColor removed in flutter_map >=8 (wrap in Container if needed)
            ),
          ],
        ),

        // All map overlays (mode indicator, zoom, attribution, add pin)
        MapOverlays(
          mapController: _controller,
          uploadMode: appState.uploadMode,
          session: session,
        ),

        // Network status indicator (top-left)
        const NetworkStatusIndicator(),
      ],
    );
  }
}


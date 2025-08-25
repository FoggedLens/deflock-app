import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';

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
  
  // Track changes that require cache clearing
  String? _lastTileTypeId;
  bool? _lastOfflineMode;
  int _mapRebuildKey = 0;
  bool _shouldClearCache = false;

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

  /// Build tile layer - uses standard URL that SimpleTileHttpClient can parse
  Widget _buildTileLayer(AppState appState) {
    final selectedTileType = appState.selectedTileType;
    final selectedProvider = appState.selectedTileProvider;
    final offlineMode = appState.offlineMode;
    
    // Create a unique cache key that includes provider, tile type, and offline mode
    // This ensures different providers/modes have separate cache entries
    String generateTileKey(String url) {
      final providerKey = selectedProvider?.id ?? 'unknown';
      final typeKey = selectedTileType?.id ?? 'unknown';
      final modeKey = offlineMode ? 'offline' : 'online';
      return '$providerKey-$typeKey-$modeKey-$url';
    }

    // Use a generic URL template that SimpleTileHttpClient recognizes
    // The actual provider URL will be built by MapDataProvider using current AppState
    // Create a completely fresh HTTP client when providers change
    // This should bypass any caching at the HTTP client level
    final httpClient = _shouldClearCache 
        ? SimpleTileHttpClient() // Fresh instance
        : _tileHttpClient; // Reuse existing
    
    if (_shouldClearCache) {
      debugPrint('[MapView] Creating fresh HTTP client to bypass cache');
    }
    
    return TileLayer(
      urlTemplate: 'https://tiles.local/{z}/{x}/{y}.png?provider=${selectedProvider?.id}&type=${selectedTileType?.id}&mode=${offlineMode ? 'offline' : 'online'}',
      userAgentPackageName: 'com.stopflock.flock_map_app',
      tileProvider: NetworkTileProvider(
        httpClient: httpClient,
        // Also disable flutter_map caching
        cachingProvider: const DisabledMapCachingProvider(),
      ),
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

    // Check if tile type OR offline mode changed and clear cache if needed
    final currentTileTypeId = appState.selectedTileType?.id;
    final currentOfflineMode = appState.offlineMode;
    
    if ((_lastTileTypeId != null && _lastTileTypeId != currentTileTypeId) ||
        (_lastOfflineMode != null && _lastOfflineMode != currentOfflineMode)) {
      // Force map rebuild with new key and destroy cache
      _mapRebuildKey++;
      _shouldClearCache = true;
      final reason = _lastTileTypeId != currentTileTypeId 
          ? 'tile type ($currentTileTypeId)' 
          : 'offline mode ($currentOfflineMode)';
      debugPrint('[MapView] *** CACHE CLEAR *** $reason changed - destroying cache $_mapRebuildKey');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[MapView] Post-frame: Clearing tile request queue');
        _tileHttpClient.clearTileQueue();
        _shouldClearCache = false;
      });
    }
    
    _lastTileTypeId = currentTileTypeId;
    _lastOfflineMode = currentOfflineMode;

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
          key: ValueKey('map_${appState.offlineMode}_${appState.selectedTileType?.id ?? 'none'}_$_mapRebuildKey'),
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
                  // Clear stale tile requests on zoom change (quietly)
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
          attribution: appState.selectedTileType?.attribution,
        ),

        // Network status indicator (top-left)
        const NetworkStatusIndicator(),
      ],
    );
  }
}


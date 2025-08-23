import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/offline_area_service.dart';
import '../models/osm_camera_node.dart';
import '../models/camera_profile.dart';
import 'debouncer.dart';
import 'tile_provider_with_cache.dart';
import 'camera_provider_with_cache.dart';
import 'map/camera_markers.dart';
import 'map/direction_cones.dart';
import 'map/map_overlays.dart';
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
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late final MapController _controller;
  final Debouncer _debounce = Debouncer(kDebounceCameraRefresh);

  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;

  late final CameraProviderWithCache _cameraProvider;
  
  // Track profile changes to trigger camera refresh
  List<CameraProfile>? _lastEnabledProfiles;
  
  // Track offline mode changes to trigger tile refresh
  bool? _lastOfflineMode;
  int _mapRebuildCounter = 0;

  @override
  void initState() {
    super.initState();
    // _debounceTileLayerUpdate removed
    OfflineAreaService();
    _controller = widget.controller;
    _initLocation();

    // Set up camera overlay caching
    _cameraProvider = CameraProviderWithCache.instance;
    _cameraProvider.addListener(_onCamerasUpdated);
    
    // Ensure initial overlays are fetched
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Set up tile refresh callback
      final tileProvider = Provider.of<TileProviderWithCache>(context, listen: false);
      tileProvider.setOnTilesCachedCallback(_onTilesCached);
      
      _refreshCamerasFromProvider();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _debounce.dispose();
    _cameraProvider.removeListener(_onCamerasUpdated);
    
    // Clean up tile refresh callback
    try {
      final tileProvider = Provider.of<TileProviderWithCache>(context, listen: false);
      tileProvider.setOnTilesCachedCallback(null);
    } catch (e) {
      // Context might be disposed already - that's okay
    }
    
    super.dispose();
  }

  void _onCamerasUpdated() {
    if (mounted) setState(() {});
  }

  void _onTilesCached() {
    // When new tiles are cached, just trigger a widget rebuild
    // This should cause the TileLayer to re-render with cached tiles
    if (mounted) {
      setState(() {});
    }
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

    // Check if offline mode changed and force complete map rebuild
    final currentOfflineMode = appState.offlineMode;
    if (_lastOfflineMode != null && _lastOfflineMode != currentOfflineMode) {
      // Offline mode changed - increment counter to force FlutterMap rebuild
      _mapRebuildCounter++;
      debugPrint('[MapView] Offline mode changed, forcing map rebuild #$_mapRebuildCounter');
    }
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
          key: ValueKey('map_rebuild_$_mapRebuildCounter'),
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
              // Request more cameras on any map movement/zoom at valid zoom level
              // This ensures cameras load even when zooming without panning (like with zoom buttons)
              if (pos.zoom >= 10) {
                _debounce(_refreshCamerasFromProvider);
              }
            },
          ),
          children: [
            TileLayer(
              tileProvider: Provider.of<TileProviderWithCache>(context),
              urlTemplate: 'unused-{z}-{x}-{y}',
              tileSize: 256,
              tileBuilder: (ctx, tileWidget, tileImage) {
                try {
                  final str = tileImage.toString();
                  final regex = RegExp(r'TileCoordinate\((\d+), (\d+), (\d+)\)');
                  final match = regex.firstMatch(str);
                  if (match != null) {
                    final x = match.group(1);
                    final y = match.group(2);
                    final z = match.group(3);
                    final key = '$z/$x/$y';
                    final bytes = TileProviderWithCache.tileCache[key];
                    if (bytes != null && bytes.isNotEmpty) {
                      return Image.memory(bytes, gaplessPlayback: true, fit: BoxFit.cover);
                    }
                  }
                  return tileWidget;
                } catch (e) {
                  print('tileBuilder error: $e for tileImage: ${tileImage.toString()}');
                  return tileWidget;
                }
              },
            ),
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
      ],
    );
  }
}


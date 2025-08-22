import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/map_data_provider.dart';
import '../services/offline_area_service.dart';
import '../models/osm_camera_node.dart';
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
  final MapDataProvider _mapDataProvider = MapDataProvider();
  final Debouncer _debounce = Debouncer(kDebounceCameraRefresh);

  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;

  late final CameraProviderWithCache _cameraProvider;

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
      _refreshCamerasFromProvider();
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _debounce.dispose();
    _cameraProvider.removeListener(_onCamerasUpdated);
    super.dispose();
  }

  void _onCamerasUpdated() {
    if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.session;

    // Only update cameras when map moves or profiles/mode actually change (not every build!)
    // _refreshCamerasFromProvider() is now only called from map movement and relevant change handlers.

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
          key: ValueKey(appState.offlineMode),
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
              // Only request more cameras if the user navigated the map (and at valid zoom)
              if (gesture && pos.zoom >= 10) {
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
              }
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


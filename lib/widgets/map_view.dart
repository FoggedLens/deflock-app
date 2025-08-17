import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/io_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/map_data_provider.dart';
import '../services/offline_area_service.dart';
import '../models/osm_camera_node.dart';
import 'debouncer.dart';
import 'camera_tag_sheet.dart';
import 'tile_provider_with_cache.dart';
import 'camera_provider_with_cache.dart';
import 'package:flock_map_app/dev_config.dart';

// --- Smart marker widget for camera with single/double tap distinction
class _CameraMapMarker extends StatefulWidget {
  final OsmCameraNode node;
  final MapController mapController;
  const _CameraMapMarker({required this.node, required this.mapController, Key? key}) : super(key: key);

  @override
  State<_CameraMapMarker> createState() => _CameraMapMarkerState();
}

class _CameraMapMarkerState extends State<_CameraMapMarker> {
  Timer? _tapTimer;
  // From dev_config.dart for build-time parameters
  static const Duration tapTimeout = kMarkerTapTimeout;

  void _onTap() {
    _tapTimer = Timer(tapTimeout, () {
      showModalBottomSheet(
        context: context,
        builder: (_) => CameraTagSheet(node: widget.node),
        showDragHandle: true,
      );
    });
  }

  void _onDoubleTap() {
    _tapTimer?.cancel();
    widget.mapController.move(widget.node.coord, widget.mapController.camera.zoom + 1);
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onDoubleTap: _onDoubleTap,
      child: const Icon(Icons.videocam, color: Colors.orange),
    );
  }
}

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
        final markers = <Marker>[
          ...cameras
            .where((n) => n.coord.latitude != 0 || n.coord.longitude != 0)
            .where((n) => n.coord.latitude.abs() <= 90 && n.coord.longitude.abs() <= 180)
            .map((n) => Marker(
              point: n.coord,
              width: 24,
              height: 24,
              child: _CameraMapMarker(node: n, mapController: _controller),
            )),
          if (_currentLatLng != null)
            Marker(
              point: _currentLatLng!,
              width: 16,
              height: 16,
              child: const Icon(Icons.my_location, color: Colors.blue),
            ),
        ];

        final overlays = <Polygon>[
          if (session != null && session.target != null)
            _buildCone(session.target!, session.directionDegrees, zoom),
          ...cameras
              .where((n) => n.hasDirection && n.directionDeg != null)
              .where((n) => n.coord.latitude != 0 || n.coord.longitude != 0)
              .where((n) => n.coord.latitude.abs() <= 90 && n.coord.longitude.abs() <= 180)
              .map((n) => _buildCone(n.coord, n.directionDeg!, zoom)),
        ];
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
              padding: EdgeInsets.only(left: 8, bottom: kScaleBarBottom), // from dev_config, above attribution & BottomAppBar
              textStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              lineColor: Colors.black,
              strokeWidth: 3,
              // backgroundColor removed in flutter_map >=8 (wrap in Container if needed)
            ),
          ],
        ),

        // MODE INDICATOR badge (top-right)
        if (appState.uploadMode == UploadMode.sandbox || appState.uploadMode == UploadMode.simulate)
          Positioned(
            top: 18,
            right: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: appState.uploadMode == UploadMode.sandbox
                    ? Colors.orange.withOpacity(0.90)
                    : Colors.deepPurple.withOpacity(0.80),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0,2)),
                ],
              ),
              child: Text(
                appState.uploadMode == UploadMode.sandbox
                  ? 'SANDBOX MODE'
                  : 'SIMULATE',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),

        // Zoom indicator, positioned above scale bar
        Positioned(
          left: 10,
          bottom: kZoomIndicatorBottom, // from dev_config
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.52),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Builder(
              builder: (context) {
                final zoom = _controller.camera.zoom;
                return Text(
                  'Zoom: ${zoom.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
        ),
        // Attribution overlay
        Positioned(
          bottom: kAttributionBottom, // from dev_config
          left: 10,
          child: Container(
            color: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: const Text(
              '© OpenStreetMap and contributors',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),

        // Fixed pin when adding camera
        if (session != null)
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: Offset(0, kAddPinYOffset),
                child: Icon(Icons.place, size: 40, color: Colors.redAccent),
              ),
            ),
          ),
      ],
    );
  }

  Polygon _buildCone(LatLng origin, double bearingDeg, double zoom) {
    final halfAngle = kDirectionConeHalfAngle;
    final length = kDirectionConeBaseLength * math.pow(2, 15 - zoom);

    LatLng _project(double deg) {
      final rad = deg * math.pi / 180;
      final dLat = length * math.cos(rad);
      final dLon =
          length * math.sin(rad) / math.cos(origin.latitude * math.pi / 180);
      return LatLng(origin.latitude + dLat, origin.longitude + dLon);
    }

    final left = _project(bearingDeg - halfAngle);
    final right = _project(bearingDeg + halfAngle);

    return Polygon(
      points: [origin, left, right, origin],
      color: Colors.redAccent.withOpacity(0.25),
      borderColor: Colors.redAccent,
      borderStrokeWidth: 1,
    );
  }
}


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

class DataProviderTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    return DataProviderImage(coords, options);
  }
}

class DataProviderImage extends ImageProvider<DataProviderImage> {
  final TileCoordinates coords;
  final TileLayer options;
  DataProviderImage(this.coords, this.options);

  @override
  Future<DataProviderImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<DataProviderImage>(this);
  }

  @override
  ImageStreamCompleter load(
      DataProviderImage key,
      Future<ui.Codec> Function(Uint8List, {int? cacheWidth, int? cacheHeight}) decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(DataProviderImage key, Future<ui.Codec> Function(Uint8List, {int? cacheWidth, int? cacheHeight}) decode) async {
    final z = key.coords.z;
    final x = key.coords.x;
    final y = key.coords.y;

    try {
      final bytes = await MapDataProvider().getTile(z: z, x: x, y: y);
      if (bytes.isEmpty) throw Exception("Empty image bytes for $z/$x/$y");
      return await decode(Uint8List.fromList(bytes));
    } catch (e) {
      // Optionally: provide an error tile
      print('[MapView] Failed to load OSM tile for $z/$x/$y: $e');
      // Return a blank pixel or a fallback error tile of your design
      return await decode(Uint8List.fromList(_transparentPng));
    }
  }

  // A tiny 1x1 transparent PNG
  static const List<int> _transparentPng = [
    137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,
    0,0,0,1,0,0,0,1,8,6,0,0,0,31,21,196,137,
    0,0,0,10,73,68,65,84,8,153,99,0,1,0,0,5,
    0,1,13,10,42,100,0,0,0,0,73,69,78,68,174,66,
    96,130];
}

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
  static const Duration tapTimeout = Duration(milliseconds: 250);

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
  final Debouncer _debounce = Debouncer(const Duration(milliseconds: 500));

  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;

  List<OsmCameraNode> _cameras = [];
  List<String> _lastProfileIds = [];
  UploadMode? _lastUploadMode;

  void _maybeRefreshCameras(AppState appState) {
    final currProfileIds = appState.enabledProfiles.map((p) => p.id).toList();
    final currMode = appState.uploadMode;
    if (_lastProfileIds.isEmpty ||
        currProfileIds.length != _lastProfileIds.length ||
        !_lastProfileIds.asMap().entries.every((entry) => currProfileIds[entry.key] == entry.value) ||
        _lastUploadMode != currMode) {
      // If this is first load, or list/ids/mode changed, refetch
      _debounce(() => _refreshCameras(appState));
      _lastProfileIds = List.from(currProfileIds);
      _lastUploadMode = currMode;
    }
  }

  @override
  void initState() {
    super.initState();
    // Kick off offline area loading as soon as map loads
    OfflineAreaService();
    _controller = widget.controller;
    _initLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _debounce.dispose();
    super.dispose();
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
        _controller.move(latLng, _controller.camera.zoom);
      }
    });
  }

  Future<void> _refreshCameras(AppState appState) async {
    LatLngBounds? bounds;
    try {
      bounds = _controller.camera.visibleBounds;
    } catch (_) {
      return; // controller not ready yet
    }
    final cams = await _mapDataProvider.getCameras(
      bounds: bounds,
      profiles: appState.enabledProfiles,
      uploadMode: appState.uploadMode,
      // MapSource.auto (default) will prefer Overpass for now
    );
    if (mounted) setState(() => _cameras = cams);
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

    // Refetch only if profiles or mode changed
    // This avoids repeated fetches on every build
    // We track last seen values (local to the State class)
    _maybeRefreshCameras(appState);

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

    // Camera markers first, then GPS dot, so blue dot is always on top
    final markers = <Marker>[ 
      ..._cameras.map(
        (n) => Marker(
          point: n.coord,
          width: 24,
          height: 24,
          child: _CameraMapMarker(node: n, mapController: _controller),
        ),
      ),
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
      ..._cameras
          .where((n) => n.hasDirection && n.directionDeg != null)
          .map((n) => _buildCone(n.coord, n.directionDeg!, zoom)),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: _currentLatLng ?? LatLng(37.7749, -122.4194),
            initialZoom: 15,
            maxZoom: 19,
            onPositionChanged: (pos, gesture) {
              if (gesture) widget.onUserGesture();
              if (session != null) {
                appState.updateSession(target: pos.center);
              }
              _debounce(() => _refreshCameras(appState));
            },
          ),
          children: [
            TileLayer(
              tileProvider: DataProviderTileProvider(),
              urlTemplate: '', // Not used by custom provider
              tileSize: 256,
              // Any other TileLayer customization as needed
            ),
            PolygonLayer(polygons: overlays),
            MarkerLayer(markers: markers),
            // Built-in scale bar from flutter_map 
            Scalebar(
              alignment: Alignment.bottomLeft,
              padding: EdgeInsets.only(left: 8, bottom: 54), // above attribution
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
          bottom: 92,
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
          bottom: 20,
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
          const IgnorePointer(
            child: Center(
              child: Icon(Icons.place, size: 40, color: Colors.redAccent),
            ),
          ),
      ],
    );
  }

  Polygon _buildCone(LatLng origin, double bearingDeg, double zoom) {
    const halfAngle = 15.0;
    final length = 0.0012 * math.pow(2, 15 - zoom);

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


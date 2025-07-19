import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/overpass_service.dart';
import '../models/osm_camera_node.dart';
import 'debouncer.dart';

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.followMe,
    required this.onUserGesture,
  });

  final bool followMe;
  final VoidCallback onUserGesture;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _controller = MapController();
  final OverpassService _overpass = OverpassService();
  final Debouncer _debounce = Debouncer(const Duration(milliseconds: 500));

  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;

  List<OsmCameraNode> _cameras = [];

  @override
  void initState() {
    super.initState();
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
    final cams = await _overpass.fetchCameras(bounds, appState.enabledProfiles);
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

    // If we just entered add‑mode and no target yet, seed it with current map center.
    if (session != null && session.target == null) {
      try {
        final center = _controller.camera.center;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => appState.updateSession(target: center),
        );
      } catch (_) {
        // controller not ready yet; will update onPositionChanged soon
      }
    }

    final zoom = _safeZoom();

    final markers = <Marker>[
      if (_currentLatLng != null)
        Marker(
          point: _currentLatLng!,
          width: 16,
          height: 16,
          child: const Icon(Icons.my_location, color: Colors.blue),
        ),
      ..._cameras.map(
        (n) => Marker(
          point: n.coord,
          width: 24,
          height: 24,
          child: const Icon(Icons.videocam, color: Colors.orange),
        ),
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
            center: _currentLatLng ?? LatLng(37.7749, -122.4194),
            zoom: 15,
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
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flock_map_app',
            ),
            PolygonLayer(polygons: overlays),
            MarkerLayer(markers: markers),
          ],
        ),
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
    final length = 0.002 * math.pow(2, 15 - zoom); // scale with zoom

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
      isFilled: true,
      color: Colors.redAccent.withOpacity(0.25),
      borderColor: Colors.redAccent,
      borderStrokeWidth: 1,
    );
  }
}


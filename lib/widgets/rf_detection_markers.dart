import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../dev_config.dart';
import '../models/rf_detection.dart';

/// Map marker widget for an RF detection with single/double tap distinction.
class RfDetectionMapMarker extends StatefulWidget {
  final RfDetection detection;
  final MapController mapController;
  final void Function(RfDetection)? onDetectionTap;
  final bool enabled;

  const RfDetectionMapMarker({
    required this.detection,
    required this.mapController,
    this.onDetectionTap,
    this.enabled = true,
    super.key,
  });

  @override
  State<RfDetectionMapMarker> createState() => _RfDetectionMapMarkerState();
}

class _RfDetectionMapMarkerState extends State<RfDetectionMapMarker> {
  Timer? _tapTimer;
  static const Duration tapTimeout = kMarkerTapTimeout;

  void _onTap() {
    if (!widget.enabled) return;

    _tapTimer = Timer(tapTimeout, () {
      widget.onDetectionTap?.call(widget.detection);
    });
  }

  void _onDoubleTap() {
    if (!widget.enabled) return;
    final pos = widget.detection.bestPosition;
    if (pos == null) return;

    _tapTimer?.cancel();
    widget.mapController.move(
      pos,
      widget.mapController.camera.zoom + kNodeDoubleTapZoomDelta,
    );
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
      child: _RfDetectionIcon(detection: widget.detection),
    );
  }
}

/// Visual icon for an RF detection marker.
/// Unsubmitted: orange ring. Submitted (linked to OSM): green ring with check.
class _RfDetectionIcon extends StatelessWidget {
  final RfDetection detection;

  const _RfDetectionIcon({required this.detection});

  @override
  Widget build(BuildContext context) {
    final isSubmitted = detection.isSubmitted;
    final alertLevel = detection.alertLevel;

    // Ring color based on alert level and submission state
    final Color ringColor;
    if (isSubmitted) {
      ringColor = Colors.green;
    } else {
      switch (alertLevel) {
        case 3:
          ringColor = const Color(0xFFFF4444); // Confirmed — red
        case 2:
          ringColor = const Color(0xFFFF8800); // Suspicious — orange
        case 1:
          ringColor = const Color(0xFFFFBB00); // Info — yellow
        default:
          ringColor = const Color(0xFF888888); // None — grey
      }
    }

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ringColor.withOpacity(0.3),
        border: Border.all(color: ringColor, width: 2.5),
      ),
      child: isSubmitted
          ? const Icon(Icons.check, size: 10, color: Colors.white)
          : null,
    );
  }
}

/// Builder for RF detection marker layer.
class RfDetectionMarkersBuilder {
  static List<Marker> buildRfDetectionMarkers({
    required List<RfDetection> detections,
    required MapController mapController,
    void Function(RfDetection)? onDetectionTap,
    bool shouldDimAll = false,
    bool enabled = true,
  }) {
    final markers = <Marker>[];

    for (final detection in detections) {
      final pos = detection.bestPosition;
      if (pos == null) continue;
      if (!_isValidCoordinate(pos)) continue;

      markers.add(
        Marker(
          point: pos,
          width: 20,
          height: 20,
          child: Opacity(
            opacity: shouldDimAll ? 0.5 : 1.0,
            child: RfDetectionMapMarker(
              detection: detection,
              mapController: mapController,
              onDetectionTap: onDetectionTap,
              enabled: enabled,
            ),
          ),
        ),
      );
    }

    return markers;
  }

  static bool _isValidCoordinate(LatLng coord) {
    return (coord.latitude != 0 || coord.longitude != 0) &&
        coord.latitude.abs() <= 90 &&
        coord.longitude.abs() <= 180;
  }
}

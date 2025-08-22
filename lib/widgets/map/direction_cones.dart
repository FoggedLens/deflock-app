import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app_state.dart';
import '../../dev_config.dart';
import '../../models/osm_camera_node.dart';

/// Helper class to build direction cone polygons for cameras
class DirectionConesBuilder {
  static List<Polygon> buildDirectionCones({
    required List<OsmCameraNode> cameras,
    required double zoom,
    AddCameraSession? session,
  }) {
    final overlays = <Polygon>[];
    
    // Add session cone if in add-camera mode
    if (session != null && session.target != null) {
      overlays.add(_buildCone(
        session.target!, 
        session.directionDegrees, 
        zoom,
      ));
    }
    
    // Add cones for cameras with direction
    overlays.addAll(
      cameras
        .where(_isValidCameraWithDirection)
        .map((n) => _buildCone(
          n.coord, 
          n.directionDeg!, 
          zoom,
          isPending: _isPendingUpload(n),
        ))
    );
    
    return overlays;
  }

  static bool _isValidCameraWithDirection(OsmCameraNode node) {
    return node.hasDirection && 
           node.directionDeg != null &&
           (node.coord.latitude != 0 || node.coord.longitude != 0) &&
           node.coord.latitude.abs() <= 90 && 
           node.coord.longitude.abs() <= 180;
  }

  static bool _isPendingUpload(OsmCameraNode node) {
    return node.tags.containsKey('_pending_upload') && 
           node.tags['_pending_upload'] == 'true';
  }

  static Polygon _buildCone(
    LatLng origin, 
    double bearingDeg, 
    double zoom, {
    bool isPending = false,
  }) {
    final halfAngle = kDirectionConeHalfAngle;
    final length = kDirectionConeBaseLength * math.pow(2, 15 - zoom);

    LatLng project(double deg) {
      final rad = deg * math.pi / 180;
      final dLat = length * math.cos(rad);
      final dLon =
          length * math.sin(rad) / math.cos(origin.latitude * math.pi / 180);
      return LatLng(origin.latitude + dLat, origin.longitude + dLon);
    }

    final left = project(bearingDeg - halfAngle);
    final right = project(bearingDeg + halfAngle);

    // Use purple color for pending uploads
    final color = isPending ? Colors.purple : Colors.redAccent;

    return Polygon(
      points: [origin, left, right, origin],
      color: color.withOpacity(0.25),
      borderColor: color,
      borderStrokeWidth: 1,
    );
  }
}
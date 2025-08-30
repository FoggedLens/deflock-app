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
    AddNodeSession? session,
    EditNodeSession? editSession,
  }) {
    final overlays = <Polygon>[];
    
    // Add session cone if in add-camera mode and profile requires direction
    if (session != null && session.target != null && session.profile.requiresDirection) {
      overlays.add(_buildCone(
        session.target!, 
        session.directionDegrees, 
        zoom,
        isSession: true,
      ));
    }
    
    // Add edit session cone if in edit-camera mode and profile requires direction
    if (editSession != null && editSession.profile.requiresDirection) {
      overlays.add(_buildCone(
        editSession.target, 
        editSession.directionDegrees, 
        zoom,
        isSession: true,
      ));
    }
    
    // Add cones for cameras with direction (but exclude camera being edited)
    overlays.addAll(
      cameras
        .where((n) => _isValidCameraWithDirection(n) && 
                     (editSession == null || n.id != editSession.originalNode.id))
        .map((n) => _buildCone(
          n.coord, 
          n.directionDeg!, 
          zoom,
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
    bool isSession = false,
  }) {
    final halfAngle = kDirectionConeHalfAngle;
    final length = kDirectionConeBaseLength * math.pow(2, 15 - zoom);
    
    // Number of points to create the arc (more = smoother curve)
    const int arcPoints = 12;

    LatLng project(double deg) {
      final rad = deg * math.pi / 180;
      final dLat = length * math.cos(rad);
      final dLon =
          length * math.sin(rad) / math.cos(origin.latitude * math.pi / 180);
      return LatLng(origin.latitude + dLat, origin.longitude + dLon);
    }

    // Build pizza slice with curved edge
    final points = <LatLng>[origin];
    
    // Add arc points from left to right
    for (int i = 0; i <= arcPoints; i++) {
      final angle = bearingDeg - halfAngle + (i * 2 * halfAngle / arcPoints);
      points.add(project(angle));
    }
    
    // Close the shape back to origin
    points.add(origin);

    return Polygon(
      points: points,
      color: kDirectionConeColor.withOpacity(0.25),
      borderColor: kDirectionConeColor,
      borderStrokeWidth: 1,
    );
  }
}
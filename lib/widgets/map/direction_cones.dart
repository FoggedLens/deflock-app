import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app_state.dart';
import '../../dev_config.dart';
import '../../models/osm_node.dart';

/// Helper class to build direction cone polygons for cameras
class DirectionConesBuilder {
  static List<Polygon> buildDirectionCones({
    required List<OsmNode> cameras,
    required double zoom,
    AddNodeSession? session,
    EditNodeSession? editSession,
    required BuildContext context,
  }) {
    final overlays = <Polygon>[];
    
    // Add session cone if in add-camera mode and profile requires direction
    if (session != null && session.target != null && session.profile?.requiresDirection == true) {
      overlays.add(_buildCone(
        session.target!, 
        session.directionDegrees, 
        zoom,
        context: context,
        isSession: true,
      ));
    }
    
    // Add edit session cone if in edit-camera mode and profile requires direction
    if (editSession != null && editSession.profile?.requiresDirection == true) {
      overlays.add(_buildCone(
        editSession.target, 
        editSession.directionDegrees, 
        zoom,
        context: context,
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
          context: context,
        ))
    );
    
    return overlays;
  }

  static bool _isValidCameraWithDirection(OsmNode node) {
    return node.hasDirection && 
           node.directionDeg != null &&
           (node.coord.latitude != 0 || node.coord.longitude != 0) &&
           node.coord.latitude.abs() <= 90 && 
           node.coord.longitude.abs() <= 180;
  }

  static bool _isPendingUpload(OsmNode node) {
    return node.tags.containsKey('_pending_upload') && 
           node.tags['_pending_upload'] == 'true';
  }

  static Polygon _buildCone(
    LatLng origin, 
    double bearingDeg, 
    double zoom, {
    required BuildContext context,
    bool isPending = false,
    bool isSession = false,
  }) {
    final halfAngle = kDirectionConeHalfAngle;
    
    // Calculate pixel-based radii
    final outerRadiusPx = kNodeIconDiameter + (kNodeIconDiameter * kDirectionConeBaseLength);
    final innerRadiusPx = kNodeIconDiameter + (2 * getNodeRingThickness(context));
    
    // Convert pixels to coordinate distances with zoom scaling
    final pixelToCoordinate = 0.00001 * math.pow(2, 15 - zoom);
    final outerRadius = outerRadiusPx * pixelToCoordinate;
    final innerRadius = innerRadiusPx * pixelToCoordinate;
    
    // Number of points for the outer arc (within our directional range)
    const int arcPoints = 12;

    LatLng project(double deg, double distance) {
      final rad = deg * math.pi / 180;
      final dLat = distance * math.cos(rad);
      final dLon =
          distance * math.sin(rad) / math.cos(origin.latitude * math.pi / 180);
      return LatLng(origin.latitude + dLat, origin.longitude + dLon);
    }

    // Build outer arc points only within our directional sector
    final points = <LatLng>[];
    
    // Add outer arc points from left to right (counterclockwise for proper polygon winding)
    for (int i = 0; i <= arcPoints; i++) {
      final angle = bearingDeg - halfAngle + (i * 2 * halfAngle / arcPoints);
      points.add(project(angle, outerRadius));
    }
    
    // Add inner arc points from right to left (to close the donut shape)
    for (int i = arcPoints; i >= 0; i--) {
      final angle = bearingDeg - halfAngle + (i * 2 * halfAngle / arcPoints);
      points.add(project(angle, innerRadius));
    }

    return Polygon(
      points: points,
      color: kDirectionConeColor.withOpacity(kDirectionConeOpacity),
      borderColor: kDirectionConeColor,
      borderStrokeWidth: getDirectionConeBorderWidth(context),
    );
  }
}
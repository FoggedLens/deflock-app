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
    
    // Add session cones if in add-camera mode and profile requires direction
    if (session != null && session.target != null && session.profile?.requiresDirection == true) {
      // Add current working direction (full opacity)
      overlays.add(_buildCone(
        session.target!, 
        session.directionDegrees, 
        zoom,
        context: context,
        isSession: true,
        isActiveDirection: true,
      ));
      
      // Add other directions (reduced opacity)
      for (int i = 0; i < session.directions.length; i++) {
        if (i != session.currentDirectionIndex) {
          overlays.add(_buildCone(
            session.target!,
            session.directions[i],
            zoom,
            context: context,
            isSession: true,
            isActiveDirection: false,
          ));
        }
      }
    }
    
    // Add edit session cones if in edit-camera mode and profile requires direction
    if (editSession != null && editSession.profile?.requiresDirection == true) {
      // Add current working direction (full opacity)
      overlays.add(_buildCone(
        editSession.target, 
        editSession.directionDegrees, 
        zoom,
        context: context,
        isSession: true,
        isActiveDirection: true,
      ));
      
      // Add other directions (reduced opacity)
      for (int i = 0; i < editSession.directions.length; i++) {
        if (i != editSession.currentDirectionIndex) {
          overlays.add(_buildCone(
            editSession.target,
            editSession.directions[i],
            zoom,
            context: context,
            isSession: true,
            isActiveDirection: false,
          ));
        }
      }
    }
    
    // Add cones for cameras with direction (but exclude camera being edited)
    for (final node in cameras) {
      if (_isValidCameraWithDirection(node) && 
          (editSession == null || node.id != editSession.originalNode.id)) {
        // Build a cone for each direction
        for (final direction in node.directionDeg) {
          overlays.add(_buildCone(
            node.coord, 
            direction, 
            zoom,
            context: context,
          ));
        }
      }
    }
    
    return overlays;
  }

  static bool _isValidCameraWithDirection(OsmNode node) {
    return node.hasDirection && 
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
    bool isActiveDirection = true,
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

    // Adjust opacity based on direction state
    double opacity = kDirectionConeOpacity;
    if (isSession && !isActiveDirection) {
      opacity = kDirectionConeOpacity * 0.4; // Reduced opacity for inactive session directions
    }

    return Polygon(
      points: points,
      color: kDirectionConeColor.withOpacity(opacity),
      borderColor: kDirectionConeColor,
      borderStrokeWidth: getDirectionConeBorderWidth(context),
    );
  }
}
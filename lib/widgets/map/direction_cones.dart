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
    
    // Add session cones if in add-camera mode and profile requires direction AND we have directions
    if (session != null && 
        session.target != null && 
        session.profile?.requiresDirection == true && 
        session.directions.isNotEmpty) {
      final sessionFov = session.profile?.fov ?? (kDirectionConeHalfAngle * 2);
      
      // Add current working direction (full opacity)
      overlays.add(_buildConeWithFov(
        session.target!, 
        session.directionDegrees, 
        sessionFov,
        zoom,
        context: context,
        isSession: true,
        isActiveDirection: true,
      ));
      
      // Add other directions (reduced opacity)
      for (int i = 0; i < session.directions.length; i++) {
        if (i != session.currentDirectionIndex) {
          overlays.add(_buildConeWithFov(
            session.target!,
            session.directions[i],
            sessionFov,
            zoom,
            context: context,
            isSession: true,
            isActiveDirection: false,
          ));
        }
      }
    }
    
    // Add edit session cones if in edit-camera mode and profile requires direction AND we have directions
    if (editSession != null && 
        editSession.profile?.requiresDirection == true && 
        editSession.directions.isNotEmpty) {
      final sessionFov = editSession.profile?.fov ?? (kDirectionConeHalfAngle * 2);
      
      // Add current working direction (full opacity)
      overlays.add(_buildConeWithFov(
        editSession.target, 
        editSession.directionDegrees, 
        sessionFov,
        zoom,
        context: context,
        isSession: true,
        isActiveDirection: true,
      ));
      
      // Add other directions (reduced opacity)
      for (int i = 0; i < editSession.directions.length; i++) {
        if (i != editSession.currentDirectionIndex) {
          overlays.add(_buildConeWithFov(
            editSession.target,
            editSession.directions[i],
            sessionFov,
            zoom,
            context: context,
            isSession: true,
            isActiveDirection: false,
          ));
        }
      }
    }
    
    // Add cones for cameras with direction (but exclude camera being edited)
    // Only show at sufficient zoom where direction is meaningful
    if (zoom >= kDirectionConeMinZoomLevel) {
      for (final node in cameras) {
        if (_isValidCameraWithDirection(node) &&
            (editSession == null || node.id != editSession.originalNode.id)) {
          // Build a cone for each direction+fov pair
          for (final directionFov in node.directionFovPairs) {
            overlays.add(_buildConeWithFov(
              node.coord,
              directionFov.centerDegrees,
              directionFov.fovDegrees,
              zoom,
              context: context,
            ));
          }
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

  /// Build cone with variable FOV width - new method for range notation support
  static Polygon _buildConeWithFov(
    LatLng origin, 
    double bearingDeg, 
    double fovDegrees,
    double zoom, {
    required BuildContext context,
    bool isPending = false,
    bool isSession = false,
    bool isActiveDirection = true,
  }) {
    return _buildConeInternal(
      origin: origin,
      bearingDeg: bearingDeg,
      halfAngleDeg: fovDegrees / 2,
      zoom: zoom,
      context: context,
      isPending: isPending,
      isSession: isSession,
      isActiveDirection: isActiveDirection,
    );
  }

  /// Internal cone building method that handles the actual rendering
  /// Builds a wedge/pie shape emanating from the camera center
  static Polygon _buildConeInternal({
    required LatLng origin,
    required double bearingDeg,
    required double halfAngleDeg,
    required double zoom,
    required BuildContext context,
    bool isPending = false,
    bool isSession = false,
    bool isActiveDirection = true,
  }) {
    // Handle full circle case (360-degree FOV)
    // Use 179.5 threshold to account for floating point precision
    if (halfAngleDeg >= 179.5) {
      return _buildFullCircle(
        origin: origin,
        zoom: zoom,
        context: context,
        isSession: isSession,
        isActiveDirection: isActiveDirection,
      );
    }

    // Calculate pixel-based outer radius using scaled marker diameter
    final diameter = getScaledNodeDiameter(zoom);
    final outerRadiusPx = diameter + (diameter * kDirectionConeBaseLength);

    // Convert pixels to coordinate distances with zoom scaling
    final pixelToCoordinate = 0.00001 * math.pow(2, 15 - zoom);
    final outerRadius = outerRadiusPx * pixelToCoordinate;

    // Smooth arc: scale points by FOV width
    final arcPoints = math.max(kDirectionConeMinArcPoints, (kDirectionConeArcPoints * halfAngleDeg / 90).round());

    LatLng project(double deg, double distance) {
      final rad = deg * math.pi / 180;
      final dLat = distance * math.cos(rad);
      final dLon =
          distance * math.sin(rad) / math.cos(origin.latitude * math.pi / 180);
      return LatLng(origin.latitude + dLat, origin.longitude + dLon);
    }

    // Build wedge/pie shape: origin → outer arc → auto-closes back to origin
    final points = <LatLng>[origin];

    for (int i = 0; i <= arcPoints; i++) {
      final angle = bearingDeg - halfAngleDeg + (i * 2 * halfAngleDeg / arcPoints);
      points.add(project(angle, outerRadius));
    }

    // Adjust opacity based on direction state
    double opacity = kDirectionConeOpacity;
    if (isSession && !isActiveDirection) {
      opacity = kDirectionConeOpacity * 0.4; // Reduced opacity for inactive session directions
    }

    return Polygon(
      points: points,
      color: kDirectionConeColor.withValues(alpha: opacity),
      borderColor: kDirectionConeColor,
      borderStrokeWidth: getDirectionConeBorderWidth(context),
    );
  }

  /// Build a full circle for 360-degree FOV cases
  static Polygon _buildFullCircle({
    required LatLng origin,
    required double zoom,
    required BuildContext context,
    bool isSession = false,
    bool isActiveDirection = true,
  }) {
    // Calculate pixel-based radius using scaled marker diameter
    final diameter = getScaledNodeDiameter(zoom);
    final outerRadiusPx = diameter + (diameter * kDirectionConeBaseLength);

    // Convert pixels to coordinate distances with zoom scaling
    final pixelToCoordinate = 0.00001 * math.pow(2, 15 - zoom);
    final outerRadius = outerRadiusPx * pixelToCoordinate;

    const int circlePoints = 60;
    final points = <LatLng>[];

    LatLng project(double deg, double distance) {
      final rad = deg * math.pi / 180;
      final dLat = distance * math.cos(rad);
      final dLon =
          distance * math.sin(rad) / math.cos(origin.latitude * math.pi / 180);
      return LatLng(origin.latitude + dLat, origin.longitude + dLon);
    }

    for (int i = 0; i < circlePoints; i++) {
      final angle = (i * 360.0 / circlePoints) % 360.0;
      points.add(project(angle, outerRadius));
    }

    // Adjust opacity based on direction state
    double opacity = kDirectionConeOpacity;
    if (isSession && !isActiveDirection) {
      opacity = kDirectionConeOpacity * 0.4;
    }

    return Polygon(
      points: points,
      color: kDirectionConeColor.withValues(alpha: opacity),
      borderColor: kDirectionConeColor,
      borderStrokeWidth: getDirectionConeBorderWidth(context),
    );
  }
}
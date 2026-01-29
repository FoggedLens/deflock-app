import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app_state.dart';
import '../../dev_config.dart';
import '../../models/osm_node.dart';
import '../../models/direction_fov.dart';

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
    
    // Add edit session cones if in edit-camera mode and profile requires direction
    if (editSession != null && editSession.profile?.requiresDirection == true) {
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

  /// Legacy method for backward compatibility - uses dev_config FOV
  static Polygon _buildCone(
    LatLng origin, 
    double bearingDeg, 
    double zoom, {
    required BuildContext context,
    bool isPending = false,
    bool isSession = false,
    bool isActiveDirection = true,
  }) {
    return _buildConeInternal(
      origin: origin,
      bearingDeg: bearingDeg,
      halfAngleDeg: kDirectionConeHalfAngle,
      zoom: zoom,
      context: context,
      isPending: isPending,
      isSession: isSession,
      isActiveDirection: isActiveDirection,
    );
  }

  /// Internal cone building method that handles the actual rendering
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
    print("DEBUG: halfAngleDeg = $halfAngleDeg, bearing = $bearingDeg");
    if (halfAngleDeg >= 179.5) {
      print("DEBUG: Using full circle for 360° FOV");
      return _buildFullCircle(
        origin: origin,
        zoom: zoom,
        context: context,
        isSession: isSession,
        isActiveDirection: isActiveDirection,
      );
    }
    print("DEBUG: Using normal cone for FOV = ${halfAngleDeg * 2}°");
    
    // Calculate pixel-based radii
    final outerRadiusPx = kNodeIconDiameter + (kNodeIconDiameter * kDirectionConeBaseLength);
    final innerRadiusPx = kNodeIconDiameter + (2 * getNodeRingThickness(context));
    
    // Convert pixels to coordinate distances with zoom scaling
    final pixelToCoordinate = 0.00001 * math.pow(2, 15 - zoom);
    final outerRadius = outerRadiusPx * pixelToCoordinate;
    final innerRadius = innerRadiusPx * pixelToCoordinate;
    
    // Number of points for the outer arc (within our directional range)
    // Scale arc points based on FOV width for better rendering
    final baseArcPoints = 12;
    final arcPoints = math.max(6, (baseArcPoints * halfAngleDeg / 45).round());

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
      final angle = bearingDeg - halfAngleDeg + (i * 2 * halfAngleDeg / arcPoints);
      points.add(project(angle, outerRadius));
    }
    
    // Add inner arc points from right to left (to close the donut shape)
    for (int i = arcPoints; i >= 0; i--) {
      final angle = bearingDeg - halfAngleDeg + (i * 2 * halfAngleDeg / arcPoints);
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

  /// Build a full circle for 360-degree FOV cases
  /// Returns just the outer circle - we'll handle the donut effect differently
  static Polygon _buildFullCircle({
    required LatLng origin,
    required double zoom,
    required BuildContext context,
    bool isSession = false,
    bool isActiveDirection = true,
  }) {
    print("DEBUG: Building full circle - isSession: $isSession, isActiveDirection: $isActiveDirection");
    
    // Calculate pixel-based radii  
    final outerRadiusPx = kNodeIconDiameter + (kNodeIconDiameter * kDirectionConeBaseLength);
    
    // Convert pixels to coordinate distances with zoom scaling
    final pixelToCoordinate = 0.00001 * math.pow(2, 15 - zoom);
    final outerRadius = outerRadiusPx * pixelToCoordinate;
    
    print("DEBUG: Outer radius: $outerRadius, zoom: $zoom");
    
    // Create simple filled circle - no donut complexity
    const int circlePoints = 60;
    final points = <LatLng>[];

    LatLng project(double deg, double distance) {
      final rad = deg * math.pi / 180;
      final dLat = distance * math.cos(rad);
      final dLon =
          distance * math.sin(rad) / math.cos(origin.latitude * math.pi / 180);
      return LatLng(origin.latitude + dLat, origin.longitude + dLon);
    }
    
    // Add outer circle points - simple complete circle
    for (int i = 0; i <= circlePoints; i++) { // Note: <= to ensure closure
      final angle = (i * 360.0 / circlePoints) % 360.0;
      points.add(project(angle, outerRadius));
    }

    print("DEBUG: Created ${points.length} points for full circle");

    // Adjust opacity based on direction state
    double opacity = kDirectionConeOpacity;
    if (isSession && !isActiveDirection) {
      opacity = kDirectionConeOpacity * 0.4;
    }

    return Polygon(
      points: points,
      color: kDirectionConeColor.withOpacity(opacity),
      borderColor: kDirectionConeColor,
      borderStrokeWidth: getDirectionConeBorderWidth(context),
    );
  }
}
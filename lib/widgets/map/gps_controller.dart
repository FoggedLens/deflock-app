import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../app_state.dart' show FollowMeMode;
import '../../services/proximity_alert_service.dart';
import '../../models/osm_node.dart';
import '../../models/node_profile.dart';

/// Manages GPS location tracking, follow-me modes, and location-based map animations.
/// Handles GPS permissions, position streams, and follow-me behavior.
class GpsController {
  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;

  /// Get the current GPS location (if available)
  LatLng? get currentLocation => _currentLatLng;

  /// Initialize GPS location tracking
  Future<void> initializeLocation() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      debugPrint('[GpsController] Location permission denied');
      return;
    }

    _positionSub = Geolocator.getPositionStream().listen((Position position) {
      final latLng = LatLng(position.latitude, position.longitude);
      _currentLatLng = latLng;
      debugPrint('[GpsController] GPS position updated: ${latLng.latitude}, ${latLng.longitude}');
    });
  }

  /// Retry location initialization (e.g., after permission granted)
  Future<void> retryLocationInit() async {
    debugPrint('[GpsController] Retrying location initialization');
    await initializeLocation();
  }

  /// Handle follow-me mode changes and animate map accordingly
  void handleFollowMeModeChange({
    required FollowMeMode newMode,
    required FollowMeMode oldMode,
    required AnimatedMapController controller,
    VoidCallback? onMapMovedProgrammatically,
  }) {
    debugPrint('[GpsController] Follow-me mode changed: $oldMode → $newMode');
    
    // Only act when follow-me is first enabled and we have a current location
    if (newMode != FollowMeMode.off && 
        oldMode == FollowMeMode.off && 
        _currentLatLng != null) {
      
      try {
        if (newMode == FollowMeMode.follow) {
          controller.animateTo(
            dest: _currentLatLng!,
            zoom: controller.mapController.camera.zoom,
            duration: dev.kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
          onMapMovedProgrammatically?.call();
        } else if (newMode == FollowMeMode.rotating) {
          // When switching to rotating mode, reset to north-up first
          controller.animateTo(
            dest: _currentLatLng!,
            zoom: controller.mapController.camera.zoom,
            rotation: 0.0,
            duration: dev.kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
          onMapMovedProgrammatically?.call();
        }
      } catch (e) {
        debugPrint('[GpsController] MapController not ready for follow-me change: $e');
      }
    }
  }

  /// Process GPS position updates and handle follow-me animations
  void processPositionUpdate({
    required Position position,
    required FollowMeMode followMeMode,
    required AnimatedMapController controller,
    required VoidCallback onLocationUpdated,
    // Optional parameters for proximity alerts
    bool proximityAlertsEnabled = false,
    int proximityAlertDistance = 200,
    List<OsmNode> nearbyNodes = const [],
    List<NodeProfile> enabledProfiles = const [],
    // Optional callback when map is moved programmatically
    VoidCallback? onMapMovedProgrammatically,

  }) {
    final latLng = LatLng(position.latitude, position.longitude);
    _currentLatLng = latLng;
    
    // Notify that location was updated (for setState, etc.)
    onLocationUpdated();
    
    // Check proximity alerts if enabled
    if (proximityAlertsEnabled && nearbyNodes.isNotEmpty) {
      ProximityAlertService().checkProximity(
        userLocation: latLng,
        nodes: nearbyNodes,
        enabledProfiles: enabledProfiles,
        alertDistance: proximityAlertDistance,
      );
    }
    
    // Handle follow-me animations if enabled - use current mode from app state
    if (followMeMode != FollowMeMode.off) {
      debugPrint('[GpsController] GPS position update: ${latLng.latitude}, ${latLng.longitude}, follow-me: $followMeMode');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (followMeMode == FollowMeMode.follow) {
            // Follow position only, keep current rotation
            controller.animateTo(
              dest: latLng,
              zoom: controller.mapController.camera.zoom,
              rotation: controller.mapController.camera.rotation,
              duration: dev.kFollowMeAnimationDuration,
              curve: Curves.easeOut,
            );
            
            // Notify that we moved the map programmatically (for node refresh)
            onMapMovedProgrammatically?.call();
          } else if (followMeMode == FollowMeMode.rotating) {
            // Follow position and rotation based on heading
            final heading = position.heading;
            final speed = position.speed; // Speed in m/s
            
            // Only apply rotation if moving fast enough to avoid wild spinning when stationary
            final shouldRotate = !speed.isNaN && speed >= dev.kMinSpeedForRotationMps && !heading.isNaN;
            final rotation = shouldRotate ? -heading : controller.mapController.camera.rotation;
            
            controller.animateTo(
              dest: latLng,
              zoom: controller.mapController.camera.zoom,
              rotation: rotation,
              duration: dev.kFollowMeAnimationDuration,
              curve: Curves.easeOut,
            );
            
            // Notify that we moved the map programmatically (for node refresh)
            onMapMovedProgrammatically?.call();
          }
        } catch (e) {
          debugPrint('[GpsController] MapController not ready for position animation: $e');
        }
      });
    }
  }

  /// Initialize GPS with custom position processing callback
  Future<void> initializeWithCallback({
    required FollowMeMode followMeMode,
    required AnimatedMapController controller,
    required VoidCallback onLocationUpdated,
    required FollowMeMode Function() getCurrentFollowMeMode,
    required bool Function() getProximityAlertsEnabled,
    required int Function() getProximityAlertDistance,
    required List<OsmNode> Function() getNearbyNodes,
    required List<NodeProfile> Function() getEnabledProfiles,
    VoidCallback? onMapMovedProgrammatically,

  }) async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      debugPrint('[GpsController] Location permission denied');
      return;
    }

    _positionSub = Geolocator.getPositionStream().listen((Position position) {
      // Get the current follow-me mode from the app state each time
      final currentFollowMeMode = getCurrentFollowMeMode();
      final proximityAlertsEnabled = getProximityAlertsEnabled();
      final proximityAlertDistance = getProximityAlertDistance();
      final nearbyNodes = getNearbyNodes();
      final enabledProfiles = getEnabledProfiles();
      processPositionUpdate(
        position: position,
        followMeMode: currentFollowMeMode,
        controller: controller,
        onLocationUpdated: onLocationUpdated,
        proximityAlertsEnabled: proximityAlertsEnabled,
        proximityAlertDistance: proximityAlertDistance,
        nearbyNodes: nearbyNodes,
        enabledProfiles: enabledProfiles,
        onMapMovedProgrammatically: onMapMovedProgrammatically,
      );
    });
  }

  /// Dispose of GPS resources
  void dispose() {
    _positionSub?.cancel();
    _positionSub = null;
    debugPrint('[GpsController] GPS controller disposed');
  }
}
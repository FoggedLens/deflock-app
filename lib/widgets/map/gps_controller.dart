import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../screens/home_screen.dart' show FollowMeMode;

/// Manages GPS location tracking, follow-me modes, and location-based map animations.
/// Handles GPS permissions, position streams, and follow-me behavior.
class GpsController {
  StreamSubscription<Position>? _positionSub;
  LatLng? _currentLatLng;
  FollowMeMode _currentFollowMeMode = FollowMeMode.off;

  /// Get the current GPS location (if available)
  LatLng? get currentLocation => _currentLatLng;
  
  /// Get the current follow-me mode
  FollowMeMode get currentFollowMeMode => _currentFollowMeMode;

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
  }) {
    // Update the stored follow-me mode
    _currentFollowMeMode = newMode;
    debugPrint('[GpsController] Follow-me mode changed: $oldMode → $newMode');
    
    // Only act when follow-me is first enabled and we have a current location
    if (newMode != FollowMeMode.off && 
        oldMode == FollowMeMode.off && 
        _currentLatLng != null) {
      
      try {
        if (newMode == FollowMeMode.northUp) {
          controller.animateTo(
            dest: _currentLatLng!,
            zoom: controller.mapController.camera.zoom,
            duration: kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
        } else if (newMode == FollowMeMode.rotating) {
          // When switching to rotating mode, reset to north-up first
          controller.animateTo(
            dest: _currentLatLng!,
            zoom: controller.mapController.camera.zoom,
            rotation: 0.0,
            duration: kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
        }
      } catch (e) {
        debugPrint('[GpsController] MapController not ready for follow-me change: $e');
      }
    }
  }

  /// Process GPS position updates and handle follow-me animations
  void processPositionUpdate({
    required Position position,
    required AnimatedMapController controller,
    required VoidCallback onLocationUpdated,
  }) {
    final latLng = LatLng(position.latitude, position.longitude);
    _currentLatLng = latLng;
    
    // Notify that location was updated (for setState, etc.)
    onLocationUpdated();
    
    // Handle follow-me animations if enabled - use current stored mode, not parameter
    if (_currentFollowMeMode != FollowMeMode.off) {
      debugPrint('[GpsController] GPS position update: ${latLng.latitude}, ${latLng.longitude}, follow-me: $_currentFollowMeMode');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (_currentFollowMeMode == FollowMeMode.northUp) {
            // Follow position only, keep current rotation
            controller.animateTo(
              dest: latLng,
              zoom: controller.mapController.camera.zoom,
              duration: kFollowMeAnimationDuration,
              curve: Curves.easeOut,
            );
          } else if (_currentFollowMeMode == FollowMeMode.rotating) {
            // Follow position and rotation based on heading
            final heading = position.heading;
            final speed = position.speed; // Speed in m/s
            
            // Only apply rotation if moving fast enough to avoid wild spinning when stationary
            final shouldRotate = !speed.isNaN && speed >= kMinSpeedForRotationMps && !heading.isNaN;
            final rotation = shouldRotate ? -heading : controller.mapController.camera.rotation;
            
            controller.animateTo(
              dest: latLng,
              zoom: controller.mapController.camera.zoom,
              rotation: rotation,
              duration: kFollowMeAnimationDuration,
              curve: Curves.easeOut,
            );
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
  }) async {
    // Store the initial follow-me mode
    _currentFollowMeMode = followMeMode;
    
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      debugPrint('[GpsController] Location permission denied');
      return;
    }

    _positionSub = Geolocator.getPositionStream().listen((Position position) {
      processPositionUpdate(
        position: position,
        controller: controller,
        onLocationUpdated: onLocationUpdated,
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
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
  bool _hasLocation = false;
  Timer? _retryTimer;

  /// Get the current GPS location (if available)
  LatLng? get currentLocation => _currentLatLng;
  
  /// Whether we currently have a valid GPS location
  bool get hasLocation => _hasLocation;

  /// Initialize GPS location tracking
  Future<void> initializeLocation() async {
    // Check if location services are enabled first
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GpsController] Location services disabled');
      _hasLocation = false;
      _scheduleRetry();
      return;
    }

    final perm = await Geolocator.requestPermission();
    debugPrint('[GpsController] Location permission result: $perm');
    
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      debugPrint('[GpsController] Precise location permission denied, trying approximate location');
      
      // Try approximate location as fallback
      try {
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 10),
        );
        debugPrint('[GpsController] Approximate location available, proceeding with location stream');
        // If we got here, approximate location works, continue with stream setup below
      } catch (e) {
        debugPrint('[GpsController] Approximate location also unavailable: $e');
        _hasLocation = false;
        _scheduleRetry();
        return;
      }
    } else if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
      debugPrint('[GpsController] Location permission granted: $perm');
      // Permission is granted, continue with normal setup
    } else {
      debugPrint('[GpsController] Unexpected permission state: $perm');
      _hasLocation = false;
      _scheduleRetry();
      return;
    }

    _positionSub?.cancel(); // Cancel any existing subscription
    debugPrint('[GpsController] Starting GPS position stream');
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update when moved at least 5 meters (standard frequency)
      ),
    ).listen(
      (Position position) {
        final latLng = LatLng(position.latitude, position.longitude);
        _currentLatLng = latLng;
        if (!_hasLocation) {
          debugPrint('[GpsController] GPS location acquired');
        }
        _hasLocation = true;
        _cancelRetry(); // Got location, stop retrying
        debugPrint('[GpsController] GPS position updated: ${latLng.latitude}, ${latLng.longitude} (accuracy: ${position.accuracy}m)');
      },
      onError: (error) {
        debugPrint('[GpsController] Position stream error: $error');
        if (_hasLocation) {
          debugPrint('[GpsController] GPS location lost, starting retry attempts');
        }
        _hasLocation = false;
        _currentLatLng = null;
        _scheduleRetry(); // Lost location, start retrying
      },
    );
  }

  /// Retry location initialization (e.g., after permission granted)
  Future<void> retryLocationInit() async {
    debugPrint('[GpsController] Manual retry of location initialization');
    _cancelRetry(); // Cancel automatic retries, this is a manual retry
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
    
    // Restart position stream with appropriate frequency for new mode
    _restartPositionStream(newMode);
    
    // Only act when follow-me is first enabled and we have a current location
    if (newMode != FollowMeMode.off && 
        oldMode == FollowMeMode.off && 
        _currentLatLng != null) {
      
      try {
        if (newMode == FollowMeMode.follow) {
          controller.animateTo(
            dest: _currentLatLng!,
            zoom: controller.mapController.camera.zoom,
            duration: kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
          onMapMovedProgrammatically?.call();
        } else if (newMode == FollowMeMode.rotating) {
          // When switching to rotating mode, reset to north-up first
          controller.animateTo(
            dest: _currentLatLng!,
            zoom: controller.mapController.camera.zoom,
            rotation: 0.0,
            duration: kFollowMeAnimationDuration,
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
    _hasLocation = true;
    _cancelRetry(); // Got location, stop any retries
    
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
              duration: kFollowMeAnimationDuration,
              curve: Curves.easeOut,
            );
            
            // Notify that we moved the map programmatically (for node refresh)
            onMapMovedProgrammatically?.call();
          } else if (followMeMode == FollowMeMode.rotating) {
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
    // Check if location services are enabled first
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GpsController] Location services disabled');
      _hasLocation = false;
      _scheduleRetry();
      return;
    }

    final perm = await Geolocator.requestPermission();
    debugPrint('[GpsController] Location permission result: $perm');
    
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      debugPrint('[GpsController] Precise location permission denied, trying approximate location');
      
      // Try approximate location as fallback
      try {
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 10),
        );
        debugPrint('[GpsController] Approximate location available, proceeding with location stream');
        // If we got here, approximate location works, continue with stream setup below
      } catch (e) {
        debugPrint('[GpsController] Approximate location also unavailable: $e');
        _hasLocation = false;
        _scheduleRetry();
        return;
      }
    } else if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
      debugPrint('[GpsController] Location permission granted: $perm');
      // Permission is granted, continue with normal setup
    } else {
      debugPrint('[GpsController] Unexpected permission state: $perm');
      _hasLocation = false;
      _scheduleRetry();
      return;
    }

    _positionSub?.cancel(); // Cancel any existing subscription
    debugPrint('[GpsController] Starting GPS position stream');
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update when moved at least 5 meters (standard frequency)
      ),
    ).listen(
      (Position position) {
        if (!_hasLocation) {
          debugPrint('[GpsController] GPS location acquired');
        }
        _hasLocation = true;
        _cancelRetry(); // Got location, stop retrying
        
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
      },
      onError: (error) {
        debugPrint('[GpsController] Position stream error: $error');
        if (_hasLocation) {
          debugPrint('[GpsController] GPS location lost, starting retry attempts');
        }
        _hasLocation = false;
        _currentLatLng = null;
        onLocationUpdated(); // Notify UI that location was lost
        _scheduleRetry(); // Lost location, start retrying
      },
    );
  }

  /// Schedule periodic retry attempts to get location
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      debugPrint('[GpsController] Automatic retry of location initialization (attempt ${timer.tick})');
      initializeLocation(); // This will cancel the timer if successful
    });
  }
  
  /// Cancel any scheduled retry attempts
  void _cancelRetry() {
    if (_retryTimer != null) {
      debugPrint('[GpsController] Canceling location retry timer');
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  /// Restart position stream with frequency optimized for follow-me mode
  void _restartPositionStream(FollowMeMode followMeMode) {
    if (_positionSub == null || !_hasLocation) {
      // No active stream or no location - let normal initialization handle it
      return;
    }
    
    _positionSub?.cancel();
    
    // Use higher frequency when follow-me is enabled
    if (followMeMode != FollowMeMode.off) {
      debugPrint('[GpsController] Starting high-frequency GPS updates for follow-me mode');
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1, // Update when moved at least 1 meter
        ),
      ).listen(
        (Position position) {
          final latLng = LatLng(position.latitude, position.longitude);
          _currentLatLng = latLng;
          if (!_hasLocation) {
            debugPrint('[GpsController] GPS location acquired');
          }
          _hasLocation = true;
          _cancelRetry(); // Got location, stop retrying
          debugPrint('[GpsController] GPS position updated: ${latLng.latitude}, ${latLng.longitude} (accuracy: ${position.accuracy}m)');
        },
        onError: (error) {
          debugPrint('[GpsController] Position stream error: $error');
          if (_hasLocation) {
            debugPrint('[GpsController] GPS location lost, starting retry attempts');
          }
          _hasLocation = false;
          _currentLatLng = null;
          _scheduleRetry(); // Lost location, start retrying
        },
      );
    } else {
      debugPrint('[GpsController] Starting standard-frequency GPS updates');
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update when moved at least 5 meters
        ),
      ).listen(
        (Position position) {
          final latLng = LatLng(position.latitude, position.longitude);
          _currentLatLng = latLng;
          if (!_hasLocation) {
            debugPrint('[GpsController] GPS location acquired');
          }
          _hasLocation = true;
          _cancelRetry(); // Got location, stop retrying
          debugPrint('[GpsController] GPS position updated: ${latLng.latitude}, ${latLng.longitude} (accuracy: ${position.accuracy}m)');
        },
        onError: (error) {
          debugPrint('[GpsController] Position stream error: $error');
          if (_hasLocation) {
            debugPrint('[GpsController] GPS location lost, starting retry attempts');
          }
          _hasLocation = false;
          _currentLatLng = null;
          _scheduleRetry(); // Lost location, start retrying
        },
      );
    }
  }

  /// Dispose of GPS resources
  void dispose() {
    _positionSub?.cancel();
    _positionSub = null;
    _cancelRetry();
    debugPrint('[GpsController] GPS controller disposed');
  }
}
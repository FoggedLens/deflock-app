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
  Timer? _retryTimer;
  
  // Location state
  LatLng? _currentLocation;
  bool _hasLocation = false;
  
  // Current tracking settings
  FollowMeMode _currentFollowMeMode = FollowMeMode.off;
  
  // Callbacks - set once during initialization
  AnimatedMapController? _mapController;
  VoidCallback? _onLocationUpdated;
  FollowMeMode Function()? _getCurrentFollowMeMode;
  bool Function()? _getProximityAlertsEnabled;
  int Function()? _getProximityAlertDistance;
  List<OsmNode> Function()? _getNearbyNodes;
  List<NodeProfile> Function()? _getEnabledProfiles;
  VoidCallback? _onMapMovedProgrammatically;

  /// Get the current GPS location (if available)
  LatLng? get currentLocation => _currentLocation;
  
  /// Whether we currently have a valid GPS location
  bool get hasLocation => _hasLocation;

  /// Initialize GPS tracking with callbacks for UI integration
  Future<void> initialize({
    required AnimatedMapController mapController,
    required VoidCallback onLocationUpdated,
    required FollowMeMode Function() getCurrentFollowMeMode,
    required bool Function() getProximityAlertsEnabled,
    required int Function() getProximityAlertDistance,
    required List<OsmNode> Function() getNearbyNodes,
    required List<NodeProfile> Function() getEnabledProfiles,
    VoidCallback? onMapMovedProgrammatically,
  }) async {
    debugPrint('[GpsController] Initializing GPS controller');
    
    // Store callbacks
    _mapController = mapController;
    _onLocationUpdated = onLocationUpdated;
    _getCurrentFollowMeMode = getCurrentFollowMeMode;
    _getProximityAlertsEnabled = getProximityAlertsEnabled;
    _getProximityAlertDistance = getProximityAlertDistance;
    _getNearbyNodes = getNearbyNodes;
    _getEnabledProfiles = getEnabledProfiles;
    _onMapMovedProgrammatically = onMapMovedProgrammatically;
    
    // Start location tracking
    await _startLocationTracking();
  }

  /// Update follow-me mode and restart tracking with appropriate frequency
  void updateFollowMeMode({
    required FollowMeMode newMode,
    required FollowMeMode oldMode,
  }) {
    debugPrint('[GpsController] Follow-me mode changed: $oldMode → $newMode');
    _currentFollowMeMode = newMode;
    
    // Restart tracking with new frequency
    _startLocationTracking();
    
    // Handle initial animation when follow-me is first enabled
    if (newMode != FollowMeMode.off && 
        oldMode == FollowMeMode.off && 
        _currentLocation != null &&
        _mapController != null) {
      
      _animateToCurrentLocation(newMode);
    }
  }

  /// Manually retry location initialization (e.g., after permission granted)
  Future<void> retryLocationInit() async {
    debugPrint('[GpsController] Manual retry of location initialization');
    _cancelRetry();
    await _startLocationTracking();
  }

  /// Start or restart GPS location tracking
  Future<void> _startLocationTracking() async {
    _stopLocationTracking(); // Clean slate
    
    // Check location services availability
    if (!await _checkLocationAvailability()) {
      _scheduleRetry();
      return;
    }
    
    // Determine frequency settings based on current follow-me mode
    final settings = _getLocationSettings();
    
    debugPrint('[GpsController] Starting GPS position stream (${_currentFollowMeMode == FollowMeMode.off ? 'standard' : 'high'} frequency)');
    
    try {
      _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
        _onPositionReceived,
        onError: _onPositionError,
      );
    } catch (e) {
      debugPrint('[GpsController] Failed to start position stream: $e');
      _hasLocation = false;
      _scheduleRetry();
    }
  }

  /// Check if location services are available and permissions are granted
  Future<bool> _checkLocationAvailability() async {
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GpsController] Location services disabled');
      _hasLocation = false;
      return false;
    }

    // Check permissions
    final perm = await Geolocator.requestPermission();
    debugPrint('[GpsController] Location permission result: $perm');
    
    if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
      debugPrint('[GpsController] Location permission granted: $perm');
      return true;
    }
    
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      // Try approximate location as fallback
      debugPrint('[GpsController] Precise location permission denied, trying approximate location');
      try {
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 10),
        );
        debugPrint('[GpsController] Approximate location available');
        return true;
      } catch (e) {
        debugPrint('[GpsController] Approximate location also unavailable: $e');
      }
    }
    
    debugPrint('[GpsController] Location unavailable, permission: $perm');
    _hasLocation = false;
    return false;
  }

  /// Get location settings based on current follow-me mode
  LocationSettings _getLocationSettings() {
    if (_currentFollowMeMode != FollowMeMode.off) {
      // High frequency for follow-me modes
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 1, // Update when moved 1+ meter
      );
    } else {
      // Standard frequency when not following
      return const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update when moved 5+ meters
      );
    }
  }

  /// Handle position updates from GPS stream
  void _onPositionReceived(Position position) {
    final newLocation = LatLng(position.latitude, position.longitude);
    _currentLocation = newLocation;
    
    if (!_hasLocation) {
      debugPrint('[GpsController] GPS location acquired');
    }
    _hasLocation = true;
    _cancelRetry();
    
    debugPrint('[GpsController] GPS position updated: ${newLocation.latitude}, ${newLocation.longitude} (accuracy: ${position.accuracy}m)');
    
    // Notify UI that location was updated
    _onLocationUpdated?.call();
    
    // Handle proximity alerts
    _checkProximityAlerts(newLocation);
    
    // Handle follow-me animations
    _handleFollowMeUpdate(position, newLocation);
  }

  /// Handle position stream errors
  void _onPositionError(error) {
    debugPrint('[GpsController] Position stream error: $error');
    if (_hasLocation) {
      debugPrint('[GpsController] GPS location lost, starting retry attempts');
    }
    _hasLocation = false;
    _currentLocation = null;
    _onLocationUpdated?.call();
    _scheduleRetry();
  }

  /// Check proximity alerts if enabled
  void _checkProximityAlerts(LatLng userLocation) {
    final proximityEnabled = _getProximityAlertsEnabled?.call() ?? false;
    final nearbyNodes = _getNearbyNodes?.call() ?? [];
    
    if (proximityEnabled && nearbyNodes.isNotEmpty) {
      final alertDistance = _getProximityAlertDistance?.call() ?? 200;
      final enabledProfiles = _getEnabledProfiles?.call() ?? [];
      
      ProximityAlertService().checkProximity(
        userLocation: userLocation,
        nodes: nearbyNodes,
        enabledProfiles: enabledProfiles,
        alertDistance: alertDistance,
      );
    }
  }

  /// Handle follow-me animations and map updates
  void _handleFollowMeUpdate(Position position, LatLng location) {
    // Get current follow-me mode from app state (in case it changed)
    final followMeMode = _getCurrentFollowMeMode?.call() ?? FollowMeMode.off;
    
    if (followMeMode == FollowMeMode.off || _mapController == null) {
      return; // Not following or no map controller
    }
    
    debugPrint('[GpsController] GPS position update for follow-me: ${location.latitude}, ${location.longitude}, mode: $followMeMode');
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (followMeMode == FollowMeMode.follow) {
          // Follow position only, preserve current rotation
          _mapController!.animateTo(
            dest: location,
            zoom: _mapController!.mapController.camera.zoom,
            rotation: _mapController!.mapController.camera.rotation,
            duration: kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
        } else if (followMeMode == FollowMeMode.rotating) {
          // Follow position and rotation based on heading
          final heading = position.heading;
          final speed = position.speed;
          
          // Only apply rotation if moving fast enough to avoid wild spinning
          final shouldRotate = !speed.isNaN && speed >= kMinSpeedForRotationMps && !heading.isNaN;
          final rotation = shouldRotate ? -heading : _mapController!.mapController.camera.rotation;
          
          _mapController!.animateTo(
            dest: location,
            zoom: _mapController!.mapController.camera.zoom,
            rotation: rotation,
            duration: kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
        }
        
        // Notify that we moved the map programmatically (for node refresh)
        _onMapMovedProgrammatically?.call();
      } catch (e) {
        debugPrint('[GpsController] MapController not ready for position animation: $e');
      }
    });
  }

  /// Animate to current location when follow-me is first enabled
  void _animateToCurrentLocation(FollowMeMode mode) {
    if (_currentLocation == null || _mapController == null) return;
    
    try {
      if (mode == FollowMeMode.follow) {
        _mapController!.animateTo(
          dest: _currentLocation!,
          zoom: _mapController!.mapController.camera.zoom,
          duration: kFollowMeAnimationDuration,
          curve: Curves.easeOut,
        );
      } else if (mode == FollowMeMode.rotating) {
        // When switching to rotating mode, reset to north-up first
        _mapController!.animateTo(
          dest: _currentLocation!,
          zoom: _mapController!.mapController.camera.zoom,
          rotation: 0.0,
          duration: kFollowMeAnimationDuration,
          curve: Curves.easeOut,
        );
      }
      
      _onMapMovedProgrammatically?.call();
    } catch (e) {
      debugPrint('[GpsController] MapController not ready for initial follow-me animation: $e');
    }
  }

  /// Schedule periodic retry attempts to get location
  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      debugPrint('[GpsController] Automatic retry of location initialization (attempt ${timer.tick})');
      _startLocationTracking();
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

  /// Stop location tracking and clean up
  void _stopLocationTracking() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  /// Dispose of all GPS resources
  void dispose() {
    debugPrint('[GpsController] Disposing GPS controller');
    _stopLocationTracking();
    _cancelRetry();
    
    // Clear callbacks
    _mapController = null;
    _onLocationUpdated = null;
    _getCurrentFollowMeMode = null;
    _getProximityAlertsEnabled = null;
    _getProximityAlertDistance = null;
    _getNearbyNodes = null;
    _getEnabledProfiles = null;
    _onMapMovedProgrammatically = null;
  }
}
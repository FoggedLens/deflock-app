import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../app_state.dart' show FollowMeMode;
import '../../services/proximity_alert_service.dart';
import '../../models/osm_node.dart';
import '../../models/node_profile.dart';

/// Simple GPS controller that handles precise location permissions only.
/// Key principles: 
/// - Respect "denied forever" - stop trying
/// - Retry "denied" - user might enable later  
/// - Only works with precise location permissions
class GpsController {
  StreamSubscription<Position>? _positionSub;
  Timer? _retryTimer;
  
  // Location state
  LatLng? _currentLocation;
  bool _hasLocation = false;
  
  // Callbacks - set during initialization
  AnimatedMapController? _mapController;
  VoidCallback? _onLocationUpdated;
  FollowMeMode Function()? _getCurrentFollowMeMode;
  bool Function()? _getProximityAlertsEnabled;
  int Function()? _getProximityAlertDistance;
  List<OsmNode> Function()? _getNearbyNodes;
  List<NodeProfile> Function()? _getEnabledProfiles;
  VoidCallback? _onMapMovedProgrammatically;
  bool Function()? _isUserInteracting;
  bool Function()? _getForceLocationManager;

  /// Get the current GPS location (if available)
  LatLng? get currentLocation => _currentLocation;
  
  /// Whether we currently have a valid GPS location
  bool get hasLocation => _hasLocation;

  /// Initialize GPS tracking with callbacks
  Future<void> initialize({
    required AnimatedMapController mapController,
    required VoidCallback onLocationUpdated,
    required FollowMeMode Function() getCurrentFollowMeMode,
    required bool Function() getProximityAlertsEnabled,
    required int Function() getProximityAlertDistance,
    required List<OsmNode> Function() getNearbyNodes,
    required List<NodeProfile> Function() getEnabledProfiles,
    VoidCallback? onMapMovedProgrammatically,
    bool Function()? isUserInteracting,
    bool Function()? getForceLocationManager,
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
    _isUserInteracting = isUserInteracting;
    _getForceLocationManager = getForceLocationManager;

    // Start location tracking
    await _startLocationTracking();
  }

  /// Update follow-me mode and restart tracking with appropriate frequency
  void updateFollowMeMode({
    required FollowMeMode newMode,
    required FollowMeMode oldMode,
  }) {
    debugPrint('[GpsController] Follow-me mode changed: $oldMode → $newMode');
    
    // Restart position stream with new frequency settings
    _restartPositionStream();
    
    // Handle initial animation when follow-me is first enabled
    _handleInitialFollowMeAnimation(newMode, oldMode);
  }

  /// Restart the location provider (e.g., after changing forceLocationManager setting)
  void restartLocationProvider() {
    if (_positionSub == null) return; // No active stream to restart
    debugPrint('[GpsController] Restarting location provider for setting change');
    _stopLocationTracking();
    _startPositionStream();
  }

  /// Manual retry (e.g., user pressed follow-me button)
  Future<void> retryLocationInit() async {
    debugPrint('[GpsController] Manual retry of location initialization');
    _cancelRetry();
    await _startLocationTracking();
  }

  /// Start location tracking - checks permissions and starts stream
  Future<void> _startLocationTracking() async {
    _stopLocationTracking(); // Clean slate
    
    // Check if location services are enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[GpsController] Location services disabled');
      _hasLocation = false;
      _notifyLocationChange();
      _scheduleRetry();
      return;
    }

    // Check permissions
    final permission = await Geolocator.requestPermission();
    debugPrint('[GpsController] Location permission result: $permission');
    
    switch (permission) {
      case LocationPermission.deniedForever:
        // User said "never" - respect that and stop trying
        debugPrint('[GpsController] Location denied forever - stopping attempts');
        _hasLocation = false;
        _notifyLocationChange();
        return;
        
      case LocationPermission.denied:
        // User said "not now" - keep trying later
        debugPrint('[GpsController] Location denied - will retry later');
        _hasLocation = false;
        _notifyLocationChange();
        _scheduleRetry();
        return;
        
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        // Permission granted - start stream
        debugPrint('[GpsController] Location permission granted: $permission');
        _startPositionStream();
        return;
        
      case LocationPermission.unableToDetermine:
        // Couldn't determine permission state - treat like denied and retry
        debugPrint('[GpsController] Unable to determine permission state - will retry');
        _hasLocation = false;
        _notifyLocationChange();
        _scheduleRetry();
        return;
    }
  }

  /// Start the GPS position stream
  void _startPositionStream() {
    final followMeMode = _getCurrentFollowMeMode?.call() ?? FollowMeMode.off;
    final distanceFilter = followMeMode == FollowMeMode.off ? 5 : 1; // 5m normal, 1m follow-me
    final forceLocationManager = _getForceLocationManager?.call() ?? false;

    debugPrint('[GpsController] Starting GPS position stream (${distanceFilter}m filter, forceLocationManager: $forceLocationManager)');

    try {
      final LocationSettings locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: distanceFilter,
              forceLocationManager: forceLocationManager,
            )
          : LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: distanceFilter,
            );

      _positionSub = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        _onPositionReceived,
        onError: _onPositionError,
      );
    } catch (e) {
      debugPrint('[GpsController] Failed to start position stream: $e');
      _hasLocation = false;
      _notifyLocationChange();
      _scheduleRetry();
    }
  }

  /// Restart position stream with current follow-me settings
  void _restartPositionStream() {
    if (_positionSub == null) {
      // No active stream, let retry logic handle it
      return;
    }
    
    debugPrint('[GpsController] Restarting position stream for follow-me mode change');
    _stopLocationTracking();
    _startPositionStream();
  }

  /// Handle incoming GPS position
  void _onPositionReceived(Position position) {
    final newLocation = LatLng(position.latitude, position.longitude);
    _currentLocation = newLocation;
    
    if (!_hasLocation) {
      debugPrint('[GpsController] GPS location acquired');
    }
    _hasLocation = true;
    _cancelRetry(); // Got location, stop any retry attempts
    
    debugPrint('[GpsController] GPS position: ${newLocation.latitude}, ${newLocation.longitude} (±${position.accuracy}m)');
    
    // Notify UI
    _notifyLocationChange();
    
    // Handle proximity alerts
    _checkProximityAlerts(newLocation);
    
    // Handle follow-me animations
    _handleFollowMeUpdate(position, newLocation);
  }

  /// Handle GPS stream errors
  void _onPositionError(dynamic error) {
    debugPrint('[GpsController] Position stream error: $error');
    if (_hasLocation) {
      debugPrint('[GpsController] Lost GPS location - will retry');
    }
    _hasLocation = false;
    _currentLocation = null;
    _notifyLocationChange();
    _scheduleRetry();
  }

  /// Check proximity alerts if enabled
  void _checkProximityAlerts(LatLng userLocation) {
    final proximityEnabled = _getProximityAlertsEnabled?.call() ?? false;
    if (!proximityEnabled) return;
    
    final nearbyNodes = _getNearbyNodes?.call() ?? [];
    if (nearbyNodes.isEmpty) return;
    
    final alertDistance = _getProximityAlertDistance?.call() ?? 200;
    final enabledProfiles = _getEnabledProfiles?.call() ?? [];
    
    ProximityAlertService().checkProximity(
      userLocation: userLocation,
      nodes: nearbyNodes,
      enabledProfiles: enabledProfiles,
      alertDistance: alertDistance,
    );
  }

  /// Handle follow-me animations
  void _handleFollowMeUpdate(Position position, LatLng location) {
    final followMeMode = _getCurrentFollowMeMode?.call() ?? FollowMeMode.off;
    if (followMeMode == FollowMeMode.off || _mapController == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (_isUserInteracting?.call() == true) return;

        if (followMeMode == FollowMeMode.follow) {
          // Follow position, preserve rotation
          _mapController!.animateTo(
            dest: location,
            zoom: _mapController!.mapController.camera.zoom,
            rotation: _mapController!.mapController.camera.rotation,
            duration: kFollowMeAnimationDuration,
            curve: Curves.easeOut,
          );
        } else if (followMeMode == FollowMeMode.rotating) {
          // Follow position and heading
          final heading = position.heading;
          final speed = position.speed;
          
          // Only rotate if moving fast enough and heading is valid
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
        
        // Notify that map was moved programmatically
        _onMapMovedProgrammatically?.call();
      } catch (e) {
        debugPrint('[GpsController] Map animation error: $e');
      }
    });
  }

  /// Handle initial animation when follow-me mode is enabled
  void _handleInitialFollowMeAnimation(FollowMeMode newMode, FollowMeMode oldMode) {
    if (newMode == FollowMeMode.off || oldMode != FollowMeMode.off) {
      return; // Not enabling follow-me, or already enabled
    }
    
    if (_currentLocation == null || _mapController == null) {
      return; // No location or map controller
    }
    
    try {
      if (newMode == FollowMeMode.follow) {
        _mapController!.animateTo(
          dest: _currentLocation!,
          zoom: _mapController!.mapController.camera.zoom,
          duration: kFollowMeAnimationDuration,
          curve: Curves.easeOut,
        );
      } else if (newMode == FollowMeMode.rotating) {
        // Reset to north-up when starting rotating mode
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
      debugPrint('[GpsController] Initial follow-me animation error: $e');
    }
  }

  /// Notify UI that location status changed
  void _notifyLocationChange() {
    _onLocationUpdated?.call();
  }

  /// Schedule retry attempts for location access
  void _scheduleRetry() {
    _cancelRetry();
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      debugPrint('[GpsController] Retry attempt ${timer.tick}');
      _startLocationTracking();
    });
  }

  /// Cancel any pending retry attempts
  void _cancelRetry() {
    if (_retryTimer != null) {
      debugPrint('[GpsController] Canceling retry timer');
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  /// Stop the position stream
  void _stopLocationTracking() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  /// Clean up all resources
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
    _isUserInteracting = null;
    _getForceLocationManager = null;
  }
}
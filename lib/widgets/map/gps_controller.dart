import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

import '../../dev_config.dart';
import '../../app_state.dart' show FollowMeMode;
import '../../services/proximity_alert_service.dart';
import '../../services/coordinate_validation.dart';
import '../../services/localization_service.dart';
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

  /// Whether the live stream was started with background delivery armed, so a
  /// proximity-alerts toggle knows whether it actually needs to rebuild it.
  bool _streamIsBackgroundCapable = false;

  // Location state
  LatLng? _currentLocation;
  bool _hasLocation = false;
  
  // Callbacks - set during initialization
  AnimatedMapController? _mapController;
  VoidCallback? _onLocationUpdated;
  FollowMeMode Function()? _getCurrentFollowMeMode;
  bool Function()? _getProximityAlertsEnabled;
  int Function()? _getProximityAlertDistance;
  List<OsmNode> Function(LatLng userLocation, int radiusMeters)? _getNearbyNodes;
  List<NodeProfile> Function()? _getEnabledProfiles;
  VoidCallback? _onMapMovedProgrammatically;
  bool Function()? _isUserInteracting;

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
    required List<OsmNode> Function(LatLng userLocation, int radiusMeters) getNearbyNodes,
    required List<NodeProfile> Function() getEnabledProfiles,
    VoidCallback? onMapMovedProgrammatically,
    bool Function()? isUserInteracting,
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

  /// Force a fresh fix, e.g. when the app returns from the background.
  ///
  /// The position stream can stay silent after a resume — and a simulated
  /// location that "teleported" while the app was suspended produces no
  /// movement event at all — leaving _currentLocation stale, so proximity
  /// alerts would keep evaluating against the old position.
  Future<void> refreshLocation() async {
    debugPrint('[GpsController] Refreshing location after resume');

    // Restart the stream first: iOS often stops delivering to a subscription
    // that spanned suspension.
    if (_positionSub != null) {
      _stopLocationTracking();
      _startPositionStream();
    }

    try {
      // geolocator 10.x: getCurrentPosition takes desiredAccuracy, unlike
      // getPositionStream above which takes a LocationSettings object.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        // Match the stream's forceLocationManager: true, so the one-shot and
        // the stream cannot disagree about where we are on Android.
        forceAndroidLocationManager: true,
        timeLimit: const Duration(seconds: 10),
      );
      _onPositionReceived(position);
    } catch (e) {
      debugPrint('[GpsController] Failed to refresh location: $e');
    }
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

    // Both platforms stop feeding a backgrounded app by default, which is why
    // alerts only ever fired with the app on screen. Keeping the stream alive
    // in the background is visible to the user (persistent notification on
    // Android, blue status bar on iOS), so only ask for it when proximity
    // alerts are actually switched on.
    final background = _getProximityAlertsEnabled?.call() ?? false;

    debugPrint(
      '[GpsController] Starting GPS position stream '
      '(${distanceFilter}m filter, background=$background)',
    );

    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: _buildLocationSettings(
          distanceFilter: distanceFilter,
          background: background,
        ),
      ).listen(
        _onPositionReceived,
        onError: _onPositionError,
      );
      _streamIsBackgroundCapable = background;
    } catch (e) {
      debugPrint('[GpsController] Failed to start position stream: $e');
      _hasLocation = false;
      _notifyLocationChange();
      _scheduleRetry();
    }
  }

  /// Platform-specific location settings.
  ///
  /// When [background] is false these are exactly the old foreground-only
  /// settings, so nothing changes for users who leave proximity alerts off.
  LocationSettings _buildLocationSettings({
    required int distanceFilter,
    required bool background,
  }) {
    final locService = LocalizationService.instance;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        forceLocationManager: true,
        // Supplying this config is what makes geolocator run its
        // GeolocatorLocationService as a foreground service. Without it
        // Android throttles a backgrounded app to a few updates per hour and
        // then stops entirely, so alerts never fire.
        foregroundNotificationConfig: background
            ? ForegroundNotificationConfig(
                notificationTitle:
                    locService.t('proximityAlerts.backgroundServiceTitle'),
                notificationText:
                    locService.t('proximityAlerts.backgroundServiceText'),
                notificationChannelName:
                    locService.t('proximityAlerts.backgroundServiceChannel'),
                // Without a wake lock the system sleeps and delivers the
                // queued positions in one burst on wake — far too late to warn
                // anyone about a device they already drove past.
                enableWakeLock: true,
                setOngoing: true,
              )
            : null,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        // Pairs with UIBackgroundModes=location in Info.plist. Together they
        // stop iOS from suspending the app on background, which is what killed
        // the position stream (and therefore every alert) before.
        allowBackgroundLocationUpdates: background,
        // iOS otherwise pauses updates when it decides you have stopped moving
        // and never reliably resumes them — a silent death for alerts.
        pauseLocationUpdatesAutomatically: false,
        // The blue status bar pill. Non-negotiable honesty: the app is reading
        // location off screen and the user should be able to see that.
        showBackgroundLocationIndicator: background,
        activityType: ActivityType.otherNavigation,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );
  }

  /// Rebuild the stream when the proximity-alerts setting is toggled, so
  /// background delivery is armed (or dropped) immediately rather than at the
  /// next unrelated stream restart.
  void updateProximityAlertsEnabled(bool enabled) {
    if (_positionSub == null || _streamIsBackgroundCapable == enabled) return;

    debugPrint('[GpsController] Proximity alerts $enabled — rebuilding stream');
    _stopLocationTracking();
    _startPositionStream();
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
    // Reject malformed fixes (occasionally NaN/Infinite from the platform
    // location stack) before they reach map state.
    if (!isValidLatitude(position.latitude) || !isValidLongitude(position.longitude)) {

      debugPrint(
        '[GpsController] Ignoring invalid GPS position: '
        'lat=${position.latitude}, lng=${position.longitude}',
      );
      return;
    }


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

    final alertDistance = _getProximityAlertDistance?.call() ?? 200;

    // Look up nodes around where the user actually is, not around whatever the
    // map camera happens to show. Backgrounded, the camera never moves, so the
    // old viewport-based lookup went stale the moment you drove out of it —
    // and even in the foreground it missed alerts whenever the map was panned
    // away from your position.
    final nearbyNodes = _getNearbyNodes?.call(userLocation, alertDistance) ?? [];
    if (nearbyNodes.isEmpty) return;

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
  }
}

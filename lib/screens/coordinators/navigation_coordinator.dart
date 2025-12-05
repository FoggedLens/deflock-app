import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart' show AppState, FollowMeMode;
import '../../widgets/map_view.dart';
import '../../dev_config.dart';

/// Coordinates all navigation and routing functionality including route planning,
/// map centering, zoom management, and route visualization.
class NavigationCoordinator {
  FollowMeMode? _previousFollowMeMode; // Track follow-me mode before overview

  /// Start a route with automatic follow-me detection and appropriate centering
  void startRoute({
    required BuildContext context,
    required AnimatedMapController mapController,
    required GlobalKey<MapViewState>? mapViewKey,
  }) {
    final appState = context.read<AppState>();
    
    // Get user location and check if we should auto-enable follow-me
    LatLng? userLocation;
    bool enableFollowMe = false;
    
    try {
      userLocation = mapViewKey?.currentState?.getUserLocation();
      if (userLocation != null && appState.shouldAutoEnableFollowMe(userLocation)) {
        debugPrint('[NavigationCoordinator] Auto-enabling follow-me mode - user within 1km of start');
        appState.setFollowMeMode(FollowMeMode.follow);
        enableFollowMe = true;
      }
    } catch (e) {
      debugPrint('[NavigationCoordinator] Could not get user location for auto follow-me: $e');
    }
    
    // Start the route
    appState.startRoute();
    
    // Zoom to level 14 and center appropriately
    _zoomAndCenterForRoute(
      mapController: mapController,
      followMeEnabled: enableFollowMe,
      userLocation: userLocation,
      routeStart: appState.routeStart,
    );
  }
  
  /// Resume a route with appropriate centering
  void resumeRoute({
    required BuildContext context,
    required AnimatedMapController mapController,
    required GlobalKey<MapViewState>? mapViewKey,
  }) {
    final appState = context.read<AppState>();
    
    // Hide the overview
    appState.hideRouteOverview();
    
    // Get user location to determine centering and follow-me behavior
    LatLng? userLocation;
    try {
      userLocation = mapViewKey?.currentState?.getUserLocation();
    } catch (e) {
      debugPrint('[NavigationCoordinator] Could not get user location for route resume: $e');
    }
    
    // Determine if user is near the route path
    bool isNearRoute = false;
    if (userLocation != null && appState.routePath != null) {
      isNearRoute = _isUserNearRoute(userLocation, appState.routePath!);
    }
    
    // Choose center point and follow-me behavior
    LatLng centerPoint;
    bool shouldEnableFollowMe = false;
    
    if (isNearRoute && userLocation != null) {
      // User is near route - center on GPS and enable follow-me
      centerPoint = userLocation;
      shouldEnableFollowMe = true;
      debugPrint('[NavigationCoordinator] User near route - centering on GPS with follow-me');
    } else {
      // User far from route or no GPS - center on route start
      centerPoint = appState.routeStart ?? userLocation ?? LatLng(0, 0);
      shouldEnableFollowMe = false;
      debugPrint('[NavigationCoordinator] User far from route - centering on start without follow-me');
    }
    
    // Apply the centering and zoom
    try {
      mapController.animateTo(
        dest: centerPoint,
        zoom: kResumeNavigationZoomLevel,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOut,
      );
    } catch (e) {
      debugPrint('[NavigationCoordinator] Could not animate to resume location: $e');
    }
    
    // Set follow-me mode based on proximity
    if (shouldEnableFollowMe) {
      // Restore previous follow-me mode if user is near route
      final modeToRestore = _previousFollowMeMode ?? FollowMeMode.follow;
      appState.setFollowMeMode(modeToRestore);
      debugPrint('[NavigationCoordinator] Restored follow-me mode: $modeToRestore');
    } else {
      // Keep follow-me off if user is far from route
      debugPrint('[NavigationCoordinator] Keeping follow-me off - user far from route');
    }
    
    // Clear stored follow-me mode
    _previousFollowMeMode = null;
  }

  /// Handle navigation button press with route overview logic
  void handleNavigationButtonPress({
    required BuildContext context,
    required AnimatedMapController mapController,
  }) {
    final appState = context.read<AppState>();
    
    if (appState.showRouteButton) {
      // Route button - show route overview and zoom to show route
      // Store current follow-me mode and disable it to prevent unexpected map jumps during overview
      _previousFollowMeMode = appState.followMeMode;
      appState.setFollowMeMode(FollowMeMode.off);
      appState.showRouteOverview();
      zoomToShowFullRoute(appState: appState, mapController: mapController);
    } else {
      // Search button - toggle search mode
      if (appState.isInSearchMode) {
        // Exit search mode
        appState.clearSearchResults();
      } else {
        // Enter search mode
        try {
          final center = mapController.mapController.camera.center;
          appState.enterSearchMode(center);
        } catch (e) {
          debugPrint('[NavigationCoordinator] Could not get map center for search: $e');
          // Fallback to default location
          appState.enterSearchMode(LatLng(37.7749, -122.4194));
        }
      }
    }
  }

  /// Zoom to show the full route between start and end points
  void zoomToShowFullRoute({
    required AppState appState,
    required AnimatedMapController mapController,
  }) {
    if (appState.routeStart == null || appState.routeEnd == null) return;
    
    try {
      // Calculate the bounds of the route
      final start = appState.routeStart!;
      final end = appState.routeEnd!;
      
      // Find the center point between start and end
      final centerLat = (start.latitude + end.latitude) / 2;
      final centerLng = (start.longitude + end.longitude) / 2;
      final center = LatLng(centerLat, centerLng);
      
      // Calculate distance between points to determine appropriate zoom
      final distance = const Distance().as(LengthUnit.Meter, start, end);
      double zoom;
      if (distance < 500) {
        zoom = 16.0;
      } else if (distance < 2000) {
        zoom = 14.0;
      } else if (distance < 10000) {
        zoom = 12.0;
      } else {
        zoom = 10.0;
      }
      
      debugPrint('[NavigationCoordinator] Zooming to show full route: ${distance.toInt()}m, zoom $zoom');
      
      mapController.animateTo(
        dest: center,
        zoom: zoom,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      debugPrint('[NavigationCoordinator] Could not zoom to show full route: $e');
    }
  }

  /// Check if user location is near the route path
  bool _isUserNearRoute(LatLng userLocation, List<LatLng> routePath) {
    if (routePath.isEmpty) return false;
    
    // Check distance to each point in the route path
    for (final routePoint in routePath) {
      final distance = const Distance().as(LengthUnit.Meter, userLocation, routePoint);
      if (distance <= kRouteProximityThresholdMeters) {
        return true;
      }
    }
    return false;
  }

  /// Internal method to zoom and center for route start/resume
  void _zoomAndCenterForRoute({
    required AnimatedMapController mapController,
    required bool followMeEnabled,
    required LatLng? userLocation,
    required LatLng? routeStart,
  }) {
    try {
      LatLng centerLocation;
      
      if (followMeEnabled && userLocation != null) {
        // Center on user if follow-me is enabled
        centerLocation = userLocation;
        debugPrint('[NavigationCoordinator] Centering on user location for route start');
      } else if (routeStart != null) {
        // Center on start pin if user is far away or no GPS
        centerLocation = routeStart;
        debugPrint('[NavigationCoordinator] Centering on route start pin');
      } else {
        debugPrint('[NavigationCoordinator] No valid location to center on');
        return;
      }
      
      // Animate to zoom 14 and center location
      mapController.animateTo(
        dest: centerLocation,
        zoom: 14.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      debugPrint('[NavigationCoordinator] Could not zoom/center for route: $e');
    }
  }
}
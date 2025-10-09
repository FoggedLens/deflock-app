// lib/dev_config.dart
import 'package:flutter/material.dart';

/// Developer/build-time configuration for global/non-user-tunable constants.

// Fallback tile storage estimate (KB per tile), used when no preview tile data is available
const double kFallbackTileEstimateKb = 25.0;

// Preview tile coordinates for tile provider previews and size estimates
const int kPreviewTileZoom = 18;
const int kPreviewTileY = 101300;
const int kPreviewTileX = 41904;

// Direction cone for map view
const double kDirectionConeHalfAngle = 35.0; // degrees
const double kDirectionConeBaseLength = 5; // multiplier
const Color kDirectionConeColor = Color(0xD0767474); // FOV cone color
const double kDirectionConeOpacity = 0.6; // Fill opacity for FOV cones
const double kDirectionConeBorderWidth = 1.6 * MediaQuery.of(context).devicePixelRatio; // Border stroke width for FOV cones

// Bottom button bar positioning
const double kBottomButtonBarOffset = 4.0; // Distance from screen bottom (above safe area)
const double kButtonBarHeight = 60.0; // Button height (48) + padding (12)

// Map overlay spacing relative to button bar top
const double kAttributionSpacingAboveButtonBar = 10.0; // Attribution above button bar top
const double kZoomIndicatorSpacingAboveButtonBar = 40.0; // Zoom indicator above button bar top  
const double kScaleBarSpacingAboveButtonBar = 70.0; // Scale bar above button bar top
const double kZoomControlsSpacingAboveButtonBar = 20.0; // Zoom controls above button bar top

// Helper to calculate bottom position relative to button bar
double bottomPositionFromButtonBar(double spacingAboveButtonBar, double safeAreaBottom) {
  return safeAreaBottom + kBottomButtonBarOffset + kButtonBarHeight + spacingAboveButtonBar;
}



// Client name for OSM uploads ("created_by" tag)
const String kClientName = 'DeFlock';
// Note: Version is now dynamically retrieved from VersionService

// Development/testing features - set to false for production builds
const bool kEnableDevelopmentModes = false; // Set to false to hide sandbox/simulate modes and force production mode

// Navigation features - set to false to hide navigation UI elements while in development
const bool kEnableNavigationFeatures = kEnableDevelopmentModes; // Hide navigation until fully implemented

/// Navigation availability: only dev builds, and only when online
bool enableNavigationFeatures({required bool offlineMode}) {
  if (!kEnableDevelopmentModes) {
    return false; // Release builds: never allow navigation
  } else {
    return !offlineMode; // Dev builds: only when online
  }
}

// Marker/node interaction
const int kNodeMinZoomLevel = 10; // Minimum zoom to show nodes (Overpass)
const int kOsmApiMinZoomLevel = 13; // Minimum zoom for OSM API bbox queries (sandbox mode)
const Duration kMarkerTapTimeout = Duration(milliseconds: 250);
const Duration kDebounceCameraRefresh = Duration(milliseconds: 500);

// Follow-me mode smooth transitions
const Duration kFollowMeAnimationDuration = Duration(milliseconds: 600);
const double kMinSpeedForRotationMps = 1.0; // Minimum speed (m/s) to apply rotation

// Proximity alerts configuration
const int kProximityAlertDefaultDistance = 200; // meters
const int kProximityAlertMinDistance = 50; // meters
const int kProximityAlertMaxDistance = 1000; // meters
const Duration kProximityAlertCooldown = Duration(minutes: 10); // Cooldown between alerts for same node

// Tile/OSM fetch retry parameters (for tunable backoff)
const int kTileFetchMaxAttempts = 3;
const int kTileFetchInitialDelayMs = 4000;
const int kTileFetchJitter1Ms = 1000;
const int kTileFetchSecondDelayMs = 15000;
const int kTileFetchJitter2Ms = 4000;
const int kTileFetchThirdDelayMs = 60000;
const int kTileFetchJitter3Ms = 5000;

// User download max zoom span (user can download up to kMaxUserDownloadZoomSpan zooms above min)
const int kMaxUserDownloadZoomSpan = 7;

// Download area limits and constants
const int kMaxReasonableTileCount = 20000;
const int kAbsoluteMaxTileCount = 50000;
const int kAbsoluteMaxZoom = 23;

// Node icon configuration
const double kNodeIconDiameter = 18.0;
const double kNodeRingThickness = 2.5 * MediaQuery.of(context).devicePixelRatio;
const double kNodeDotOpacity = 0.3; // Opacity for the grey dot interior
const Color kNodeRingColorReal = Color(0xFF3036F0); // Real nodes from OSM - blue
const Color kNodeRingColorMock = Color(0xD0FFFFFF); // Add node mock point - white
const Color kNodeRingColorPending = Color(0xD09C27B0); // Submitted/pending nodes - purple
const Color kNodeRingColorEditing = Color(0xD0FF9800); // Node being edited - orange
const Color kNodeRingColorPendingEdit = Color(0xD0757575); // Original node with pending edit - grey
const Color kNodeRingColorPendingDeletion = Color(0xC0F44336); // Node pending deletion - red, slightly transparent

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
const double kDirectionConeOpacity = 0.5; // Fill opacity for FOV cones
// Base values for thickness - use helper functions below for pixel-ratio scaling
const double _kDirectionConeBorderWidthBase = 1.6;

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

// Helper to get left positioning that accounts for safe area (for landscape mode)
double leftPositionWithSafeArea(double baseLeft, EdgeInsets safeArea) {
  return baseLeft + safeArea.left;
}

// Helper to get right positioning that accounts for safe area (for landscape mode)
double rightPositionWithSafeArea(double baseRight, EdgeInsets safeArea) {
  return baseRight + safeArea.right;
}

// Helper to get top positioning that accounts for safe area
double topPositionWithSafeArea(double baseTop, EdgeInsets safeArea) {
  return baseTop + safeArea.top;
}

// Client name for OSM uploads ("created_by" tag)
const String kClientName = 'DeFlock';
// Note: Version is now dynamically retrieved from VersionService

// Suspected locations CSV URL
const String kSuspectedLocationsCsvUrl = 'https://stopflock.com/app/flock_utilities_mini_latest.csv';

// Development/testing features - set to false for production builds
const bool kEnableDevelopmentModes = true; // Set to false to hide sandbox/simulate modes and force production mode

// Navigation features - set to false to hide navigation UI elements while in development
const bool kEnableNavigationFeatures = kEnableDevelopmentModes; // Hide navigation until fully implemented

// Node editing features - set to false to temporarily disable editing
const bool kEnableNodeEdits = true; // Set to false to temporarily disable node editing

// Node extraction features - set to false to hide extract functionality for constrained nodes
const bool kEnableNodeExtraction = false; // Set to true to enable extract from way/relation feature (WIP)

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
const int kMinZoomForNodeEditingSheets = 15; // Minimum zoom to open add/edit node sheets
const int kMinZoomForOfflineDownload = 10; // Minimum zoom to download offline areas (prevents large area crashes)
const Duration kMarkerTapTimeout = Duration(milliseconds: 250);
const Duration kDebounceCameraRefresh = Duration(milliseconds: 500);

// Pre-fetch area configuration
const double kPreFetchAreaExpansionMultiplier = 3.0; // Expand visible bounds by this factor for pre-fetching
const int kPreFetchZoomLevel = 10; // Always pre-fetch at this zoom level for consistent area sizes
const int kMaxPreFetchSplitDepth = 3; // Maximum recursive splits when hitting Overpass node limit

// Data refresh configuration
const int kDataRefreshIntervalSeconds = 60; // Refresh cached data after this many seconds

// Follow-me mode smooth transitions
const Duration kFollowMeAnimationDuration = Duration(milliseconds: 600);
const double kMinSpeedForRotationMps = 1.0; // Minimum speed (m/s) to apply rotation

// Sheet content configuration
const double kMaxTagListHeightRatioPortrait = 0.3; // Maximum height for tag lists in portrait mode
const double kMaxTagListHeightRatioLandscape = 0.2; // Maximum height for tag lists in landscape mode

/// Get appropriate tag list height ratio based on screen orientation
double getTagListHeightRatio(BuildContext context) {
  final size = MediaQuery.of(context).size;
  final isLandscape = size.width > size.height;
  return isLandscape ? kMaxTagListHeightRatioLandscape : kMaxTagListHeightRatioPortrait;
}

// Proximity alerts configuration
const int kProximityAlertDefaultDistance = 400; // meters
const int kProximityAlertMinDistance = 50; // meters
const int kProximityAlertMaxDistance = 1600; // meters
const Duration kProximityAlertCooldown = Duration(minutes: 10); // Cooldown between alerts for same node

// Node proximity warning configuration (for new/edited nodes that are too close to existing ones)
const double kNodeProximityWarningDistance = 15.0; // meters - distance threshold to show warning

// Map interaction configuration
const double kNodeDoubleTapZoomDelta = 1.0; // How much to zoom in when double-tapping nodes (was 1.0)
const double kScrollWheelVelocity = 0.01; // Mouse scroll wheel zoom speed (default 0.005)
const double kPinchZoomThreshold = 0.2; // How much pinch required to start zoom (reduced for gesture race)
const double kPinchMoveThreshold = 30.0; // How much drag required for two-finger pan (default 40.0)
const double kRotationThreshold = 6.0; // Degrees of rotation required before map actually rotates (Google Maps style)

// Tile fetch retry parameters (configurable backoff system)
const int kTileFetchMaxAttempts = 16;              // Number of retry attempts before giving up
const int kTileFetchInitialDelayMs = 500;        // Base delay for first retry (1 second)
const double kTileFetchBackoffMultiplier = 1.5;   // Multiply delay by this each attempt
const int kTileFetchMaxDelayMs = 10000;            // Cap delays at this value (8 seconds max)
const int kTileFetchRandomJitterMs = 250;         // Random fuzz to add (0 to 500ms)

// User download max zoom span (user can download up to kMaxUserDownloadZoomSpan zooms above min)
const int kMaxUserDownloadZoomSpan = 7;

// Download area limits and constants
const int kMaxReasonableTileCount = 20000;
const int kAbsoluteMaxTileCount = 50000;
const int kAbsoluteMaxZoom = 23;

// Node icon configuration
const double kNodeIconDiameter = 18.0;
const double _kNodeRingThicknessBase = 2.5;
const double kNodeDotOpacity = 0.3; // Opacity for the grey dot interior
const Color kNodeRingColorReal = Color(0xFF3036F0); // Real nodes from OSM - blue
const Color kNodeRingColorMock = Color(0xD0FFFFFF); // Add node mock point - white
const Color kNodeRingColorPending = Color(0xD09C27B0); // Submitted/pending nodes - purple
const Color kNodeRingColorEditing = Color(0xD0FF9800); // Node being edited - orange
const Color kNodeRingColorPendingEdit = Color(0xD0757575); // Original node with pending edit - grey
const Color kNodeRingColorPendingDeletion = Color(0xC0F44336); // Node pending deletion - red, slightly transparent

// Direction slider control buttons configuration  
const double kDirectionButtonMinWidth = 22.0;
const double kDirectionButtonMinHeight = 32.0;

// Helper functions for pixel-ratio scaling
double getDirectionConeBorderWidth(BuildContext context) {
//  return _kDirectionConeBorderWidthBase * MediaQuery.of(context).devicePixelRatio;
  return _kDirectionConeBorderWidthBase;
}

double getNodeRingThickness(BuildContext context) {
//  return _kNodeRingThicknessBase * MediaQuery.of(context).devicePixelRatio;
  return _kNodeRingThicknessBase;
}

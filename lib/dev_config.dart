// lib/dev_config.dart
import 'package:flutter/material.dart';

/// Developer/build-time configuration for global/non-user-tunable constants.
/// Single source of truth with typed maps for settings auto-generation.

// Typed configuration maps - single definition of each constant
const Map<String, bool> _boolConfig = {
  'kEnableDevelopmentModes': true,
  'kEnableNodeEdits': true,
  'kEnableNodeExtraction': false,
};

const Map<String, int> _intConfig = {
  'kPreviewTileZoom': 18,
  'kPreviewTileY': 101300,
  'kPreviewTileX': 41904,
  'kNodeMinZoomLevel': 10,
  'kOsmApiMinZoomLevel': 13,
  'kPreFetchZoomLevel': 10,
  'kMaxPreFetchSplitDepth': 3,
  'kDataRefreshIntervalSeconds': 60,
  'kProximityAlertDefaultDistance': 400,
  'kProximityAlertMinDistance': 50,
  'kProximityAlertMaxDistance': 1600,
  'kTileFetchMaxAttempts': 16,
  'kTileFetchInitialDelayMs': 500,
  'kTileFetchMaxDelayMs': 10000,
  'kTileFetchRandomJitterMs': 250,
  'kMaxUserDownloadZoomSpan': 7,
  'kMaxReasonableTileCount': 20000,
  'kAbsoluteMaxTileCount': 50000,
  'kAbsoluteMaxZoom': 23,
};

const Map<String, double> _doubleConfig = {
  'kFallbackTileEstimateKb': 25.0,
  'kDirectionConeHalfAngle': 35.0,
  'kDirectionConeBaseLength': 5.0,
  'kDirectionConeOpacity': 0.5,
  '_kDirectionConeBorderWidthBase': 1.6,
  'kBottomButtonBarOffset': 4.0,
  'kButtonBarHeight': 60.0,
  'kAttributionSpacingAboveButtonBar': 10.0,
  'kZoomIndicatorSpacingAboveButtonBar': 40.0,
  'kScaleBarSpacingAboveButtonBar': 70.0,
  'kZoomControlsSpacingAboveButtonBar': 20.0,
  'kPreFetchAreaExpansionMultiplier': 3.0,
  'kMinSpeedForRotationMps': 1.0,
  'kMaxTagListHeightRatioPortrait': 0.3,
  'kMaxTagListHeightRatioLandscape': 0.2,
  'kNodeDoubleTapZoomDelta': 1.0,
  'kScrollWheelVelocity': 0.01,
  'kPinchZoomThreshold': 0.2,
  'kPinchMoveThreshold': 30.0,
  'kRotationThreshold': 6.0,
  'kNodeIconDiameter': 18.0,
  '_kNodeRingThicknessBase': 2.5,
  'kNodeDotOpacity': 0.3,
  'kDirectionButtonMinWidth': 22.0,
  'kDirectionButtonMinHeight': 32.0,
  'kTileFetchBackoffMultiplier': 1.5,
};

const Map<String, String> _stringConfig = {
  'kClientName': 'DeFlock', // Read-only in settings
  'kSuspectedLocationsCsvUrl': 'https://stopflock.com/app/flock_utilities_mini_latest.csv',
};

const Map<String, Color> _colorConfig = {
  'kDirectionConeColor': Color(0xD0767474),
  'kNodeRingColorReal': Color(0xFF3036F0),
  'kNodeRingColorMock': Color(0xD0FFFFFF),
  'kNodeRingColorPending': Color(0xD09C27B0),
  'kNodeRingColorEditing': Color(0xD0FF9800),
  'kNodeRingColorPendingEdit': Color(0xD0757575),
  'kNodeRingColorPendingDeletion': Color(0xC0F44336),
};

const Map<String, Duration> _durationConfig = {
  'kMarkerTapTimeout': Duration(milliseconds: 250),
  'kDebounceCameraRefresh': Duration(milliseconds: 500),
  'kFollowMeAnimationDuration': Duration(milliseconds: 600),
  'kProximityAlertCooldown': Duration(minutes: 10),
};

// Dynamic accessor class
class _DevConfig {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().replaceAll('Symbol("', '').replaceAll('")', '');
    
    // Check each typed map
    if (_boolConfig.containsKey(name)) return _boolConfig[name];
    if (_intConfig.containsKey(name)) return _intConfig[name];
    if (_doubleConfig.containsKey(name)) return _doubleConfig[name];
    if (_stringConfig.containsKey(name)) return _stringConfig[name];
    if (_colorConfig.containsKey(name)) return _colorConfig[name];
    if (_durationConfig.containsKey(name)) return _durationConfig[name];
    
    throw NoSuchMethodError.withInvocation(this, invocation);
  }
}

// Global accessor
final dynamic dev = _DevConfig();

// For settings page - combine all maps
Map<String, dynamic> get devConfigForSettings => {
  ..._boolConfig,
  ..._intConfig,
  ..._doubleConfig,
  ..._stringConfig,
  ..._colorConfig,
  ..._durationConfig,
};

// Computed constants
bool get kEnableNavigationFeatures => dev.kEnableDevelopmentModes;

// Helper to calculate bottom position relative to button bar
double bottomPositionFromButtonBar(double spacingAboveButtonBar, double safeAreaBottom) {
  return safeAreaBottom + dev.kBottomButtonBarOffset + dev.kButtonBarHeight + spacingAboveButtonBar;
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

/// Navigation availability: only dev builds, and only when online
bool enableNavigationFeatures({required bool offlineMode}) {
  if (!dev.kEnableDevelopmentModes) {
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
//  return dev._kDirectionConeBorderWidthBase * MediaQuery.of(context).devicePixelRatio;
  return dev._kDirectionConeBorderWidthBase;
}

double getNodeRingThickness(BuildContext context) {
//  return dev._kNodeRingThicknessBase * MediaQuery.of(context).devicePixelRatio;
  return dev._kNodeRingThicknessBase;
}

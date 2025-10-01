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
const double kDirectionConeHalfAngle = 30.0; // degrees
const double kDirectionConeBaseLength = 0.001; // multiplier
const Color kDirectionConeColor = Color(0xFF000000); // FOV cone color

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

// Add Camera icon vertical offset (no offset needed since circle is centered)
const double kAddPinYOffset = 0.0;

// Client name and version for OSM uploads ("created_by" tag)
const String kClientName = 'DeFlock';
const String kClientVersion = '0.9.16';

// Development/testing features - set to false for production builds
const bool kEnableDevelopmentModes = true; // Set to false to hide sandbox/simulate modes and force production mode

// Marker/node interaction
const int kCameraMinZoomLevel = 10; // Minimum zoom to show nodes (Overpass)
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

// Last map location and settings storage
const String kLastMapLatKey = 'last_map_latitude';
const String kLastMapLngKey = 'last_map_longitude';
const String kLastMapZoomKey = 'last_map_zoom';

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
const int kAbsoluteMaxZoom = 19;

// Camera icon configuration
const double kCameraIconDiameter = 20.0;
const double kCameraRingThickness = 4.0;
const double kCameraDotOpacity = 0.4; // Opacity for the grey dot interior
const Color kCameraRingColorReal = Color(0xC43F55F3); // Real nodes from OSM - blue
const Color kCameraRingColorMock = Color(0xC4FFFFFF); // Add node mock point - white
const Color kCameraRingColorPending = Color(0xC49C27B0); // Submitted/pending nodes - purple
const Color kCameraRingColorEditing = Color(0xC4FF9800); // Node being edited - orange
const Color kCameraRingColorPendingEdit = Color(0xC4757575); // Original node with pending edit - grey
const Color kCameraRingColorPendingDeletion = Color(0xA4F44336); // Node pending deletion - red, slightly transparent

// lib/dev_config.dart
import 'package:flutter/material.dart';

/// Developer/build-time configuration for global/non-user-tunable constants.
const int kWorldMinZoom = 1;
const int kWorldMaxZoom = 5;

// Example: Default tile storage estimate (KB per tile), for size estimates
const double kTileEstimateKb = 25.0;

// Direction cone for map view
const double kDirectionConeHalfAngle = 30.0; // degrees
const double kDirectionConeBaseLength = 0.001; // multiplier
const Color kDirectionConeColor = Color(0xFF111111); // FOV cone color

// Margin (bottom) for positioning the floating bottom button bar
const double kBottomButtonBarMargin = 4.0;

// Map overlay (attribution, scale bar, zoom) vertical offset from bottom edge
const double kAttributionBottomOffset = 110.0;
const double kZoomIndicatorBottomOffset = 142.0;
const double kScaleBarBottomOffset = 170.0;

// Add Camera icon vertical offset (no offset needed since circle is centered)
const double kAddPinYOffset = 0.0;

// Client name and version for OSM uploads ("created_by" tag)
const String kClientName = 'FlockMap';
const String kClientVersion = '0.8.10';

// Marker/camera interaction
const int kCameraMinZoomLevel = 10; // Minimum zoom to show cameras or warning
const Duration kMarkerTapTimeout = Duration(milliseconds: 250);
const Duration kDebounceCameraRefresh = Duration(milliseconds: 500);

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
const int kAbsoluteMaxZoom = 19;

// Camera icon configuration
const double kCameraIconDiameter = 20.0;
const double kCameraRingThickness = 4.0;
const double kCameraDotOpacity = 0.4; // Opacity for the grey dot interior
const Color kCameraRingColorReal = Color(0xC43F55F3); // Real cameras from OSM - blue
const Color kCameraRingColorMock = Color(0xC4FFFFFF); // Add camera mock point - white
const Color kCameraRingColorPending = Color(0xC49C27B0); // Submitted/pending cameras - purple
const Color kCameraRingColorEditing = Color(0xC4FF9800); // Camera being edited - orange

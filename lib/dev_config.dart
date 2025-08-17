// lib/dev_config.dart
/// Developer/build-time configuration for global/non-user-tunable constants.
const int kWorldMinZoom = 1;
const int kWorldMaxZoom = 5;

// Example: Default tile storage estimate (KB per tile), for size estimates
const double kTileEstimateKb = 25.0;

// Direction cone for map view
const double kDirectionConeHalfAngle = 20.0; // degrees
const double kDirectionConeBaseLength = 0.0012; // multiplier

// Add Camera pin vertical offset (for pin tip to match coordinate on map)
const double kAddPinYOffset = -16.0;

// Client name and version for OSM uploads ("created_by" tag)
const String kClientName = 'FlockMap';
const String kClientVersion = '0.8.1';

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

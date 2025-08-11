// lib/dev_config.dart
/// Developer/build-time configuration for global/non-user-tunable constants.
const int kWorldMinZoom = 1;
const int kWorldMaxZoom = 4;

// Example: Default tile storage estimate (KB per tile), for size estimates
const double kTileEstimateKb = 25.0;

// Direction cone for map view
const double kDirectionConeHalfAngle = 15.0; // degrees
const double kDirectionConeBaseLength = 0.0012; // multiplier

// Marker/camera interaction
const Duration kMarkerTapTimeout = Duration(milliseconds: 250);
const Duration kDebounceCameraRefresh = Duration(milliseconds: 500);
const Duration kDebounceTileLayerUpdate = Duration(milliseconds: 50);

// Tile/Network fetch retry parameters (for tunable dev backoff)
const int kTileFetchMaxAttempts = 3;
const int kTileFetchInitialDelayMs = 4000;
const int kTileFetchJitter1Ms = 1000;
const int kTileFetchSecondDelayMs = 15000;
const int kTileFetchJitter2Ms = 4000;
const int kTileFetchThirdDelayMs = 60000;
const int kTileFetchJitter3Ms = 5000;

/// Shared validation helpers for geographic coordinates and zoom levels.
///
/// Used wherever a coordinate or zoom level comes from an external source
/// (GPS fixes, persisted preferences, live map camera state) that isn't
/// guaranteed to be finite/in-range.
library;

import '../dev_config.dart' show kAbsoluteMaxZoom;

/// Validate that a latitude value is finite and within -90 to 90.
bool isValidLatitude(double value) {
  return !value.isNaN && !value.isInfinite && value >= -90.0 && value <= 90.0;
}

/// Validate that a longitude value is finite and within -180 to 180.
bool isValidLongitude(double value) {
  return !value.isNaN && !value.isInfinite && value >= -180.0 && value <= 180.0;
}

/// Validate that a zoom level is finite and within a sane range.
///
/// Defaults to 1.0 to [kAbsoluteMaxZoom]. `num` is used (rather than
/// `double`) so the `int` constant [kAbsoluteMaxZoom] can be used directly
/// as a default parameter value.
bool isValidZoom(double zoom, {num min = 1.0, num max = kAbsoluteMaxZoom}) {
  return !zoom.isNaN && !zoom.isInfinite && zoom >= min && zoom <= max;
}

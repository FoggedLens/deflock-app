/// Shared validation helpers for geographic coordinates and zoom levels.
///
/// Used anywhere a [LatLng]-like value or zoom level comes from an external
/// or platform source (GPS fixes, persisted preferences, live map camera
/// state) that isn't guaranteed to be finite/in-range. Centralizing this
/// avoids subtly inconsistent validation logic being duplicated across the
/// GPS controller, map position persistence, and live camera guards.
library;

/// Validate that a latitude or longitude value is finite and within the
/// valid range for geographic coordinates (-180 to 180).
///
/// Note: this intentionally uses the wider +/-180 range (rather than +/-90
/// for latitude) so a single helper can validate both latitude and
/// longitude values without the caller needing to track which is which.
bool isValidCoordinate(double value) {
  return !value.isNaN && !value.isInfinite && value >= -180.0 && value <= 180.0;
}

/// Validate that a zoom level is finite and within a sane range.
bool isValidZoom(double zoom, {double min = 0.0, double max = 25.0}) {
  return !zoom.isNaN && !zoom.isInfinite && zoom >= min && zoom <= max;
}

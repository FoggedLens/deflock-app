import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

/// Utility for tile calculations and lat/lon conversions for OSM offline logic

/// Normalize bounds so south ≤ north, west ≤ east, and degenerate (near-zero)
/// spans are expanded by epsilon.  Call this before storing bounds so that
/// `tileInBounds` and [computeTileList] see consistent corner ordering.
LatLngBounds normalizeBounds(LatLngBounds bounds) {
  const double epsilon = 1e-7;
  var latMin = min(bounds.southWest.latitude, bounds.northEast.latitude);
  var latMax = max(bounds.southWest.latitude, bounds.northEast.latitude);
  var lonMin = min(bounds.southWest.longitude, bounds.northEast.longitude);
  var lonMax = max(bounds.southWest.longitude, bounds.northEast.longitude);
  if ((latMax - latMin).abs() < epsilon) {
    latMin -= epsilon;
    latMax += epsilon;
  }
  if ((lonMax - lonMin).abs() < epsilon) {
    lonMin -= epsilon;
    lonMax += epsilon;
  }
  return LatLngBounds(LatLng(latMin, lonMin), LatLng(latMax, lonMax));
}

Set<List<int>> computeTileList(LatLngBounds bounds, int zMin, int zMax) {
  Set<List<int>> tiles = {};
  final normalized = normalizeBounds(bounds);
  final double latMin = normalized.south;
  final double latMax = normalized.north;
  final double lonMin = normalized.west;
  final double lonMax = normalized.east;
  for (int z = zMin; z <= zMax; z++) {
    final n = pow(2, z).toInt();
    final minTileRaw = latLonToTileRaw(latMin, lonMin, z);
    final maxTileRaw = latLonToTileRaw(latMax, lonMax, z);
    int minX = min(minTileRaw[0].floor(), maxTileRaw[0].floor()) - 1;
    int maxX = max(minTileRaw[0].ceil() - 1, maxTileRaw[0].ceil() - 1) + 1;
    int minY = min(minTileRaw[1].floor(), maxTileRaw[1].floor()) - 1;
    int maxY = max(minTileRaw[1].ceil() - 1, maxTileRaw[1].ceil() - 1) + 1;
    minX = minX.clamp(0, n - 1);
    maxX = maxX.clamp(0, n - 1);
    minY = minY.clamp(0, n - 1);
    maxY = maxY.clamp(0, n - 1);
    for (int x = minX; x <= maxX; x++) {
      for (int y = minY; y <= maxY; y++) {
        tiles.add([z, x, y]);
      }
    }
  }
  return tiles;
}

List<double> latLonToTileRaw(double lat, double lon, int zoom) {
  final n = pow(2.0, zoom);
  final xtile = (lon + 180.0) / 360.0 * n;
  final ytile = (1.0 - 
    log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * n;
  return [xtile, ytile];
}

List<int> latLonToTile(double lat, double lon, int zoom) {
  final n = pow(2.0, zoom);
  final xtile = ((lon + 180.0) / 360.0 * n).floor();
  final ytile = ((1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * n).floor();
  return [xtile, ytile];
}

/// Convert tile coordinates back to LatLng bounds
LatLngBounds tileToLatLngBounds(int x, int y, int z) {
  final n = pow(2, z);
  
  // Calculate bounds for this tile
  final lonWest = x / n * 360.0 - 180.0;
  final lonEast = (x + 1) / n * 360.0 - 180.0;
  
  // For latitude, we need to invert the mercator projection
  final latNorthRad = atan(sinh(pi * (1 - 2 * y / n)));
  final latSouthRad = atan(sinh(pi * (1 - 2 * (y + 1) / n)));
  
  final latNorth = latNorthRad * 180.0 / pi;
  final latSouth = latSouthRad * 180.0 / pi;
  
  return LatLngBounds(
    LatLng(latSouth, lonWest),   // SW corner
    LatLng(latNorth, lonEast),   // NE corner
  );
}

/// Hyperbolic sine function: sinh(x) = (e^x - e^(-x)) / 2
double sinh(double x) {
  return (exp(x) - exp(-x)) / 2;
}

/// Expand bounds by [factor] around its center point.
/// A factor of 1.0 returns the original bounds; 2.0 doubles the span.
LatLngBounds expandBounds(LatLngBounds bounds, double factor) {
  final centerLat = (bounds.north + bounds.south) / 2;
  final centerLng = (bounds.east + bounds.west) / 2;
  final latSpan = (bounds.north - bounds.south) * factor / 2;
  final lngSpan = (bounds.east - bounds.west) * factor / 2;
  return LatLngBounds(
    LatLng(centerLat - latSpan, centerLng - lngSpan),
    LatLng(centerLat + latSpan, centerLng + lngSpan),
  );
}

LatLngBounds globalWorldBounds() {
  // Use slightly shrunken bounds to avoid tile index overflow at extreme coordinates
  return LatLngBounds(LatLng(-85.0, -179.9), LatLng(85.0, 179.9));
}

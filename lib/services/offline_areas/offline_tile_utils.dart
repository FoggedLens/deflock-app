import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

/// Utility for tile calculations and lat/lon conversions for OSM offline logic

Set<List<int>> computeTileList(LatLngBounds bounds, int zMin, int zMax) {
  Set<List<int>> tiles = {};
  const double epsilon = 1e-7;
  double latMin = min(bounds.southWest.latitude, bounds.northEast.latitude);
  double latMax = max(bounds.southWest.latitude, bounds.northEast.latitude);
  double lonMin = min(bounds.southWest.longitude, bounds.northEast.longitude);
  double lonMax = max(bounds.southWest.longitude, bounds.northEast.longitude);
  // Expand degenerate/flat areas a hair
  if ((latMax - latMin).abs() < epsilon) {
    latMin -= epsilon;
    latMax += epsilon;
  }
  if ((lonMax - lonMin).abs() < epsilon) {
    lonMin -= epsilon;
    lonMax += epsilon;
  }
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

LatLngBounds globalWorldBounds() {
  // Use slightly shrunken bounds to avoid tile index overflow at extreme coordinates
  return LatLngBounds(LatLng(-85.0, -179.9), LatLng(85.0, 179.9));
}

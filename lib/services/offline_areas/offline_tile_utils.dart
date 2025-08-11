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
    final minTile = latLonToTile(latMin, lonMin, z);
    final maxTile = latLonToTile(latMax, lonMax, z);
    final minX = min(minTile[0], maxTile[0]);
    final maxX = max(minTile[0], maxTile[0]);
    final minY = min(minTile[1], maxTile[1]);
    final maxY = max(minTile[1], maxTile[1]);
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

int findDynamicMinZoom(LatLngBounds bounds, {int maxSearchZoom = 19}) {
  for (int z = 1; z <= maxSearchZoom; z++) {
    final swTile = latLonToTile(bounds.southWest.latitude, bounds.southWest.longitude, z);
    final neTile = latLonToTile(bounds.northEast.latitude, bounds.northEast.longitude, z);
    if (swTile[0] != neTile[0] || swTile[1] != neTile[1]) {
      return z - 1 > 0 ? z - 1 : 1;
    }
  }
  return maxSearchZoom;
}

LatLngBounds globalWorldBounds() {
  // Use slightly shrunken bounds to avoid tile index overflow at extreme coordinates
  return LatLngBounds(LatLng(-85.0, -179.9), LatLng(85.0, 179.9));
}

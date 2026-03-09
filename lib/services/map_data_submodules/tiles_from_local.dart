import 'dart:io';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../offline_area_service.dart';
import '../offline_areas/offline_area_models.dart';
import '../offline_areas/offline_tile_utils.dart' show latLonToTileRaw;
import '../../app_state.dart';

/// Fetch a tile from the newest offline area that matches the given provider, or throw if not found.
///
/// When [providerId] and [tileTypeId] are supplied the lookup is pinned to
/// those values (avoids a race when the user switches provider mid-flight).
/// Otherwise falls back to the current AppState selection.
Future<List<int>> fetchLocalTile({
  required int z,
  required int x,
  required int y,
  String? providerId,
  String? tileTypeId,
}) async {
  final appState = AppState.instance;
  final currentProviderId = providerId ?? appState.selectedTileProvider?.id;
  final currentTileTypeId = tileTypeId ?? appState.selectedTileType?.id;

  final offlineService = OfflineAreaService();
  await offlineService.ensureInitialized();
  final areas = offlineService.offlineAreas;
  final List<_AreaTileMatch> candidates = [];

  for (final area in areas) {
    if (area.status != OfflineAreaStatus.complete) continue;
    if (z < area.minZoom || z > area.maxZoom) continue;

    // Only consider areas that match the current provider/type
    if (area.tileProviderId != currentProviderId || area.tileTypeId != currentTileTypeId) continue;

    // O(1) bounds check instead of enumerating all tiles at this zoom level
    if (!tileInBounds(area.bounds, z, x, y)) continue;

    final tilePath = _tilePath(area.directory, z, x, y);
    final file = File(tilePath);
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) continue;
      candidates.add(_AreaTileMatch(area: area, file: file, modified: stat.modified));
    } on FileSystemException {
      continue;
    }
  }
  if (candidates.isEmpty) {
    throw Exception('Tile $z/$x/$y from provider $currentProviderId/$currentTileTypeId not found in any offline area');
  }
  candidates.sort((a, b) => b.modified.compareTo(a.modified)); // newest first
  return await candidates.first.file.readAsBytes();
}

/// O(1) check whether tile (z, x, y) falls within the given lat/lng bounds.
///
/// Reuses [latLonToTileRaw] from offline_tile_utils.dart for the Mercator
/// projection, computing only the bounding tile range instead of enumerating
/// every tile at that zoom level.
///
/// Note: Y axis is inverted in tile coordinates — north = lower Y.
@visibleForTesting
bool tileInBounds(LatLngBounds bounds, int z, int x, int y) {
  final swTile = latLonToTileRaw(bounds.south, bounds.west, z);
  final neTile = latLonToTileRaw(bounds.north, bounds.east, z);

  final minX = swTile[0].floor();
  final maxX = neTile[0].floor();
  // North → lower Y (Mercator projection inverts latitude)
  final minY = neTile[1].floor();
  final maxY = swTile[1].floor();

  return x >= minX && x <= maxX && y >= minY && y <= maxY;
}

String _tilePath(String areaDir, int z, int x, int y) =>
    '$areaDir/tiles/$z/$x/$y.png';

class _AreaTileMatch {
  final OfflineArea area;
  final File file;
  final DateTime modified;
  _AreaTileMatch({required this.area, required this.file, required this.modified});
}

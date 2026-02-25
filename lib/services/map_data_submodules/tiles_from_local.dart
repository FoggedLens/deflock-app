import 'dart:io';
import '../offline_area_service.dart';
import '../offline_areas/offline_area_models.dart';
import '../offline_areas/offline_tile_utils.dart';
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

    // Get tile coverage for area at this zoom only
    final coveredTiles = computeTileList(area.bounds, z, z);
    final hasTile = coveredTiles.any((tile) => tile[0] == z && tile[1] == x && tile[2] == y);
    if (hasTile) {
      final tilePath = _tilePath(area.directory, z, x, y);
      final file = File(tilePath);
      if (await file.exists()) {
        final stat = await file.stat();
        candidates.add(_AreaTileMatch(area: area, file: file, modified: stat.modified));
      }
    }
  }
  if (candidates.isEmpty) {
    throw Exception('Tile $z/$x/$y from provider $currentProviderId/$currentTileTypeId not found in any offline area');
  }
  candidates.sort((a, b) => b.modified.compareTo(a.modified)); // newest first
  return await candidates.first.file.readAsBytes();
}

String _tilePath(String areaDir, int z, int x, int y) =>
    '$areaDir/tiles/$z/$x/$y.png';

class _AreaTileMatch {
  final OfflineArea area;
  final File file;
  final DateTime modified;
  _AreaTileMatch({required this.area, required this.file, required this.modified});
}

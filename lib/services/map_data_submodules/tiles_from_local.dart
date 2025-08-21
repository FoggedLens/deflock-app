import 'dart:io';
import 'package:latlong2/latlong.dart';
import '../offline_area_service.dart';
import '../offline_areas/offline_area_models.dart';
import '../offline_areas/offline_tile_utils.dart';

/// Fetch a tile from the newest offline area that plausibly contains it, or throw if not found.
Future<List<int>> fetchLocalTile({required int z, required int x, required int y}) async {
  final offlineService = OfflineAreaService();
  await offlineService.ensureInitialized();
  final areas = offlineService.offlineAreas;
  final List<_AreaTileMatch> candidates = [];

  print('[fetchLocalTile] Looking for tile $z/$x/$y in ${areas.length} offline areas');

  for (final area in areas) {
    print('[fetchLocalTile] Checking area: ${area.id}, status: ${area.status}, zoom: ${area.minZoom}-${area.maxZoom}');
    
    if (area.status != OfflineAreaStatus.complete) {
      print('[fetchLocalTile] Skipping area ${area.id} - status not complete: ${area.status}');
      continue;
    }
    
    if (z < area.minZoom || z > area.maxZoom) {
      print('[fetchLocalTile] Skipping area ${area.id} - zoom $z outside range ${area.minZoom}-${area.maxZoom}');
      continue;
    }

    // Get tile coverage for area at this zoom only
    final coveredTiles = computeTileList(area.bounds, z, z);
    final hasTile = coveredTiles.any((tile) => tile[0] == z && tile[1] == x && tile[2] == y);
    print('[fetchLocalTile] Area ${area.id} covers ${coveredTiles.length} tiles at zoom $z, contains target tile: $hasTile');
    
    if (hasTile) {
      final tilePath = _tilePath(area.directory, z, x, y);
      final file = File(tilePath);
      final exists = await file.exists();
      print('[fetchLocalTile] Tile file path: $tilePath, exists: $exists');
      
      if (exists) {
        final stat = await file.stat();
        candidates.add(_AreaTileMatch(area: area, file: file, modified: stat.modified));
        print('[fetchLocalTile] Added candidate from area ${area.id}');
      }
    }
  }
  
  print('[fetchLocalTile] Found ${candidates.length} candidates for tile $z/$x/$y');
  
  if (candidates.isEmpty) {
    throw Exception('Tile $z/$x/$y not found in any offline area');
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

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:path_provider/path_provider.dart';
import 'offline_areas/offline_area_models.dart';
import 'offline_areas/offline_tile_utils.dart';
import 'offline_areas/offline_area_service_tile_fetch.dart';
import '../models/osm_camera_node.dart';

/// Service for managing download, storage, and retrieval of offline map areas and cameras.
class OfflineAreaService {
  static final OfflineAreaService _instance = OfflineAreaService._();
  factory OfflineAreaService() => _instance;
  OfflineAreaService._() {
    _loadAreasFromDisk().then((_) => _ensureAndAutoDownloadWorldArea());
  }

  final List<OfflineArea> _areas = [];
  List<OfflineArea> get offlineAreas => List.unmodifiable(_areas);

  Future<Directory> getOfflineAreaDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final areaRoot = Directory("${dir.path}/offline_areas");
    if (!areaRoot.existsSync()) {
      areaRoot.createSync(recursive: true);
    }
    return areaRoot;
  }

  Future<File> _getMetadataPath() async {
    final dir = await getOfflineAreaDir();
    return File("${dir.path}/offline_areas.json");
  }

  Future<int> getAreaSizeBytes(OfflineArea area) async {
    int total = 0;
    final dir = Directory(area.directory);
    if (await dir.exists()) {
      await for (var fse in dir.list(recursive: true)) {
        if (fse is File) {
          total += await fse.length();
        }
      }
    }
    area.sizeBytes = total;
    await saveAreasToDisk();
    return total;
  }

  Future<void> saveAreasToDisk() async {
    try {
      final file = await _getMetadataPath();
      final content = jsonEncode(_areas.map((a) => a.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save offline areas: $e');
    }
  }

  Future<void> _loadAreasFromDisk() async {
    try {
      final file = await _getMetadataPath();
      if (!(await file.exists())) return;
      final str = await file.readAsString();
      if (str.trim().isEmpty) return;
      late final List data;
      try {
        data = jsonDecode(str);
      } catch (e) {
        debugPrint('Failed to parse offline areas json: $e');
        return;
      }
      _areas.clear();
      for (final areaJson in data) {
        final area = OfflineArea.fromJson(areaJson);
        if (!Directory(area.directory).existsSync()) {
          area.status = OfflineAreaStatus.error;
        } else {
          getAreaSizeBytes(area);
        }
        _areas.add(area);
      }
    } catch (e) {
      debugPrint('Failed to load offline areas: $e');
    }
  }

  Future<void> _ensureAndAutoDownloadWorldArea() async {
    final dir = await getOfflineAreaDir();
    final worldDir = "${dir.path}/world_z1_4";
    final LatLngBounds worldBounds = globalWorldBounds();
    OfflineArea? world;
    for (final a in _areas) {
      if (a.isPermanent) { world = a; break; }
    }
    final Set<List<int>> expectedTiles = computeTileList(worldBounds, 1, 4);
    if (world != null) {
      int filesFound = 0;
      List<List<int>> missingTiles = [];
      for (final tile in expectedTiles) {
        final f = File('${world.directory}/tiles/${tile[0]}/${tile[1]}/${tile[2]}.png');
        if (f.existsSync()) {
          filesFound++;
        } else if (missingTiles.length < 10) {
          missingTiles.add(tile);
        }
      }
      if (filesFound != expectedTiles.length) {
        debugPrint('World area: missing \\${expectedTiles.length - filesFound} tiles. First few: \\$missingTiles');
      } else {
        debugPrint('World area: all tiles accounted for.');
      }
      world.tilesTotal = expectedTiles.length;
      world.tilesDownloaded = filesFound;
      world.progress = (world.tilesTotal == 0) ? 0.0 : (filesFound / world.tilesTotal);
      if (filesFound == world.tilesTotal) {
        world.status = OfflineAreaStatus.complete;
        await saveAreasToDisk();
        return;
      } else {
        world.status = OfflineAreaStatus.downloading;
        await saveAreasToDisk();
        downloadArea(
          id: world.id,
          bounds: world.bounds,
          minZoom: world.minZoom,
          maxZoom: world.maxZoom,
          directory: world.directory,
          name: world.name,
        );
        return;
      }
    }
    // If not present, create and start download
    world = OfflineArea(
      id: 'permanent_world_z1_4',
      name: 'World (zoom 1-4)',
      bounds: worldBounds,
      minZoom: 1,
      maxZoom: 4,
      directory: worldDir,
      status: OfflineAreaStatus.downloading,
      progress: 0.0,
      isPermanent: true,
      tilesTotal: expectedTiles.length,
      tilesDownloaded: 0,
    );
    _areas.insert(0, world);
    await saveAreasToDisk();
    downloadArea(
      id: world.id,
      bounds: world.bounds,
      minZoom: world.minZoom,
      maxZoom: world.maxZoom,
      directory: world.directory,
      name: world.name,
    );
  }

  Future<void> downloadArea({
    required String id,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String directory,
    void Function(double progress)? onProgress,
    void Function(OfflineAreaStatus status)? onComplete,
    String? name,
  }) async {
    OfflineArea? area;
    for (final a in _areas) {
      if (a.id == id) { area = a; break; }
    }
    if (area != null) {
      _areas.remove(area);
      final dirObj = Directory(area.directory);
      if (await dirObj.exists()) {
        await dirObj.delete(recursive: true);
      }
    }
    area = OfflineArea(
      id: id,
      name: name ?? area?.name ?? '',
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      directory: directory,
      isPermanent: area?.isPermanent ?? false,
    );
    _areas.add(area);
    await saveAreasToDisk();

    try {
      Set<List<int>> allTiles;
      if (area.isPermanent) {
        allTiles = computeTileList(globalWorldBounds(), 1, 4);
      } else {
        allTiles = computeTileList(bounds, minZoom, maxZoom);
      }
      area.tilesTotal = allTiles.length;
      const int maxPasses = 3;
      int pass = 0;
      Set<List<int>> allTilesSet = allTiles.toSet();
      Set<List<int>> tilesToFetch = allTilesSet;
      bool success = false;
      int totalDone = 0;
      while (pass < maxPasses && tilesToFetch.isNotEmpty) {
        pass++;
        int doneThisPass = 0;
        debugPrint('DownloadArea: pass #$pass for area $id. Need \\${tilesToFetch.length} tiles.');
        for (final tile in tilesToFetch) {
          if (area.status == OfflineAreaStatus.cancelled) break;
          try {
            await downloadTile(tile[0], tile[1], tile[2], directory);
            totalDone++;
            doneThisPass++;
            area.tilesDownloaded = totalDone;
            area.progress = area.tilesTotal == 0 ? 0.0 : ((area.tilesDownloaded) / area.tilesTotal);
          } catch (e) {
            debugPrint("Tile download failed for z=${tile[0]}, x=${tile[1]}, y=${tile[2]}: $e");
          }
          if (onProgress != null) onProgress(area.progress);
        }
        await getAreaSizeBytes(area);
        await saveAreasToDisk();
        Set<List<int>> missingTiles = {};
        for (final tile in allTilesSet) {
          final f = File('$directory/tiles/${tile[0]}/${tile[1]}/${tile[2]}.png');
          if (!f.existsSync()) missingTiles.add(tile);
        }
        if (missingTiles.isEmpty) {
          success = true;
          break;
        }
        tilesToFetch = missingTiles;
      }

      if (!area.isPermanent) {
        final cameras = await downloadAllCameras(bounds);
        area.cameras = cameras;
        await saveCameras(cameras, directory);
      } else {
        area.cameras = [];
      }
      await getAreaSizeBytes(area);

      if (success) {
        area.status = OfflineAreaStatus.complete;
        area.progress = 1.0;
        debugPrint('Area $id: all tiles accounted for and area marked complete.');
      } else {
        area.status = OfflineAreaStatus.error;
        debugPrint('Area $id: MISSING tiles after $maxPasses passes. First 10: \\${tilesToFetch.toList().take(10)}');
        if (!area.isPermanent) {
          final dirObj = Directory(area.directory);
          if (await dirObj.exists()) {
            await dirObj.delete(recursive: true);
          }
          _areas.remove(area);
        }
      }
      await saveAreasToDisk();
      if (onComplete != null) onComplete(area.status);
    } catch (e) {
      area.status = OfflineAreaStatus.error;
      await saveAreasToDisk();
      if (onComplete != null) onComplete(area.status);
    }
  }

  void cancelDownload(String id) async {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    area.status = OfflineAreaStatus.cancelled;
    final dir = Directory(area.directory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _areas.remove(area);
    await saveAreasToDisk();
    if (area.isPermanent) {
      _ensureAndAutoDownloadWorldArea();
    }
  }

  void deleteArea(String id) async {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    final dir = Directory(area.directory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _areas.remove(area);
    await saveAreasToDisk();
  }
}

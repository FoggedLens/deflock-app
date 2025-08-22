import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:path_provider/path_provider.dart';
import 'offline_areas/offline_area_models.dart';
import 'offline_areas/offline_tile_utils.dart';
import 'offline_areas/offline_area_service_tile_fetch.dart'; // Only used for file IO during area downloads.
import '../models/osm_camera_node.dart';
import '../app_state.dart';
import 'map_data_provider.dart';
import 'map_data_submodules/cameras_from_overpass.dart';
import 'package:flock_map_app/dev_config.dart';

/// Service for managing download, storage, and retrieval of offline map areas and cameras.
class OfflineAreaService {
  static final OfflineAreaService _instance = OfflineAreaService._();
  factory OfflineAreaService() => _instance;
  
  bool _initialized = false;
  Future<void>? _initializationFuture;
  
  OfflineAreaService._();

  final List<OfflineArea> _areas = [];
  List<OfflineArea> get offlineAreas => List.unmodifiable(_areas);
  
  /// Ensure the service is initialized (areas loaded from disk)
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    
    _initializationFuture ??= _initialize();
    await _initializationFuture;
  }
  
  Future<void> _initialize() async {
    if (_initialized) return;
    
    await _loadAreasFromDisk();
    await _ensureAndAutoDownloadWorldArea();
    _initialized = true;
  }

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
      final offlineDir = await getOfflineAreaDir();
      
      // Convert areas to JSON with relative paths for portability
      final areaJsonList = _areas.map((area) {
        final json = area.toJson();
        // Convert absolute path to relative path for storage
        if (json['directory'].toString().startsWith(offlineDir.path)) {
          final relativePath = json['directory'].toString().replaceFirst('${offlineDir.path}/', '');
          json['directory'] = relativePath;
        }
        return json;
      }).toList();
      
      final content = jsonEncode(areaJsonList);
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
        // Migrate stored directory paths to be relative for portability
        String storedDir = areaJson['directory'];
        String relativePath = storedDir;
        
        // If it's an absolute path, extract just the folder name
        if (storedDir.startsWith('/')) {
          if (storedDir.contains('/offline_areas/')) {
            final parts = storedDir.split('/offline_areas/');
            if (parts.length == 2) {
              relativePath = parts[1]; // Just the folder name (e.g., "world" or "2025-08-19...")
            }
          }
        }
        
        // Always construct absolute path at runtime
        final offlineDir = await getOfflineAreaDir();
        final fullPath = '${offlineDir.path}/$relativePath';
        
        // Update the JSON to use the full path for this session
        areaJson['directory'] = fullPath;
        
        final area = OfflineArea.fromJson(areaJson);
        
        if (!Directory(area.directory).existsSync()) {
          area.status = OfflineAreaStatus.error;
        } else {
          // Reset error status if directory now exists (fixes areas that were previously broken due to path issues)
          if (area.status == OfflineAreaStatus.error) {
            area.status = OfflineAreaStatus.complete;
          }
          
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
    final worldDir = "${dir.path}/world";
    final LatLngBounds worldBounds = globalWorldBounds();
    OfflineArea? world;
    for (final a in _areas) {
      if (a.isPermanent) { world = a; break; }
    }
    final Set<List<int>> expectedTiles = computeTileList(worldBounds, kWorldMinZoom, kWorldMaxZoom);
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
        debugPrint('World area: missing ${expectedTiles.length - filesFound} tiles. First few: $missingTiles');
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
      id: 'permanent_world',
      name: 'World (required)',
      bounds: worldBounds,
      minZoom: kWorldMinZoom,
      maxZoom: kWorldMaxZoom,
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
        allTiles = computeTileList(globalWorldBounds(), kWorldMinZoom, kWorldMaxZoom);
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
        debugPrint('DownloadArea: pass #$pass for area $id. Need ${tilesToFetch.length} tiles.');
        for (final tile in tilesToFetch) {
          if (area.status == OfflineAreaStatus.cancelled) break;
          try {
            final bytes = await MapDataProvider().getTile(
              z: tile[0], x: tile[1], y: tile[2], source: MapSource.remote);
            if (bytes.isNotEmpty) {
              await saveTileBytes(tile[0], tile[1], tile[2], directory, bytes);
            }
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
        // Calculate expanded camera bounds that cover the entire tile area at minimum zoom
        final cameraBounds = _calculateCameraBounds(bounds, minZoom);
        final cameras = await MapDataProvider().getAllCamerasForDownload(
          bounds: cameraBounds,
          profiles: AppState.instance.enabledProfiles,
        );
        area.cameras = cameras;
        await saveCameras(cameras, directory);
        debugPrint('Area $id: Downloaded ${cameras.length} cameras from expanded bounds (${cameraBounds.north.toStringAsFixed(6)}, ${cameraBounds.west.toStringAsFixed(6)}) to (${cameraBounds.south.toStringAsFixed(6)}, ${cameraBounds.east.toStringAsFixed(6)})');
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
        debugPrint('Area $id: MISSING tiles after $maxPasses passes. First 10: ${tilesToFetch.toList().take(10)}');
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
  
  /// Calculate expanded bounds that cover the entire tile area at minimum zoom
  /// This ensures we fetch all cameras that could be relevant for the offline area
  LatLngBounds _calculateCameraBounds(LatLngBounds visibleBounds, int minZoom) {
    // Get all tiles that cover the visible bounds at minimum zoom
    final tiles = computeTileList(visibleBounds, minZoom, minZoom);
    if (tiles.isEmpty) return visibleBounds;
    
    // Find the bounding box of all these tiles
    double minLat = 90.0, maxLat = -90.0;
    double minLon = 180.0, maxLon = -180.0;
    
    for (final tile in tiles) {
      final z = tile[0];
      final x = tile[1]; 
      final y = tile[2];
      
      // Convert tile coordinates back to lat/lng bounds
      final tileBounds = _tileToLatLngBounds(x, y, z);
      
      minLat = math.min(minLat, tileBounds.south);
      maxLat = math.max(maxLat, tileBounds.north);
      minLon = math.min(minLon, tileBounds.west);
      maxLon = math.max(maxLon, tileBounds.east);
    }
    
    return LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
  }
  
  /// Convert tile coordinates to LatLng bounds
  LatLngBounds _tileToLatLngBounds(int x, int y, int z) {
    final n = math.pow(2, z);
    final lonDeg = x / n * 360.0 - 180.0;
    final latRad = math.atan(_sinh(math.pi * (1 - 2 * y / n)));
    final latDeg = latRad * 180.0 / math.pi;
    
    final lonDegNext = (x + 1) / n * 360.0 - 180.0;
    final latRadNext = math.atan(_sinh(math.pi * (1 - 2 * (y + 1) / n)));
    final latDegNext = latRadNext * 180.0 / math.pi;
    
    return LatLngBounds(
      LatLng(latDegNext, lonDeg),      // SW corner
      LatLng(latDeg, lonDegNext),      // NE corner  
    );
  }
  
  /// Hyperbolic sine function: sinh(x) = (e^x - e^(-x)) / 2
  double _sinh(double x) {
    return (math.exp(x) - math.exp(-x)) / 2;
  }
}

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:path_provider/path_provider.dart';
import 'offline_areas/offline_area_models.dart';
import 'offline_areas/offline_tile_utils.dart';
import 'offline_areas/offline_area_downloader.dart';

import '../models/osm_camera_node.dart';
import '../app_state.dart';
import 'map_data_provider.dart';
import 'package:deflockapp/dev_config.dart';

/// Service for managing download, storage, and retrieval of offline map areas and cameras.
class OfflineAreaService {
  static final OfflineAreaService _instance = OfflineAreaService._();
  factory OfflineAreaService() => _instance;
  
  bool _initialized = false;
  Future<void>? _initializationFuture;
  
  OfflineAreaService._();

  final List<OfflineArea> _areas = [];
  List<OfflineArea> get offlineAreas => List.unmodifiable(_areas);
  
  /// Check if any areas are currently downloading
  bool get hasActiveDownloads => _areas.any((area) => area.status == OfflineAreaStatus.downloading);
  
  /// Cancel all active downloads (used when enabling offline mode)
  Future<void> cancelActiveDownloads() async {
    final activeAreas = _areas.where((area) => area.status == OfflineAreaStatus.downloading).toList();
    for (final area in activeAreas) {
      area.status = OfflineAreaStatus.cancelled;
      if (!area.isPermanent) {
        // Clean up non-permanent areas
        final dir = Directory(area.directory);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
        _areas.remove(area);
      }
    }
    await saveAreasToDisk();
    debugPrint('OfflineAreaService: Cancelled ${activeAreas.length} active downloads due to offline mode');
  }
  
  /// Ensure the service is initialized (areas loaded from disk)
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    
    _initializationFuture ??= _initialize();
    await _initializationFuture;
  }
  
  Future<void> _initialize() async {
    if (_initialized) return;
    
    await _loadAreasFromDisk();
    await _cleanupLegacyWorldAreas();
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



  Future<void> downloadArea({
    required String id,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String directory,
    void Function(double progress)? onProgress,
    void Function(OfflineAreaStatus status)? onComplete,
    String? name,
    String? tileProviderId,
    String? tileProviderName,
    String? tileTypeId,
    String? tileTypeName,
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
      tileProviderId: tileProviderId,
      tileProviderName: tileProviderName,
      tileTypeId: tileTypeId,
      tileTypeName: tileTypeName,
    );
    _areas.add(area);
    await saveAreasToDisk();

    try {
    final success = await OfflineAreaDownloader.downloadArea(
      area: area,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      directory: directory,
      onProgress: onProgress,
      saveAreasToDisk: saveAreasToDisk,
      getAreaSizeBytes: getAreaSizeBytes,
    );

      await getAreaSizeBytes(area);

      if (success) {
        area.status = OfflineAreaStatus.complete;
        area.progress = 1.0;
        debugPrint('Area $id: download completed successfully.');
      } else {
        area.status = OfflineAreaStatus.error;
        debugPrint('Area $id: download failed after maximum retry attempts.');
        if (!area.isPermanent) {
          final dirObj = Directory(area.directory);
          if (await dirObj.exists()) {
            await dirObj.delete(recursive: true);
          }
          _areas.remove(area);
        }
      }
      await saveAreasToDisk();
      onComplete?.call(area.status);
    } catch (e) {
      area.status = OfflineAreaStatus.error;
      await saveAreasToDisk();
      onComplete?.call(area.status);
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
  
  /// Remove any legacy world areas from previous versions
  Future<void> _cleanupLegacyWorldAreas() async {
    final worldAreas = _areas.where((area) => area.isPermanent || area.id == 'world').toList();
    
    if (worldAreas.isNotEmpty) {
      debugPrint('OfflineAreaService: Cleaning up ${worldAreas.length} legacy world area(s)');
      
      for (final area in worldAreas) {
        final dir = Directory(area.directory);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          debugPrint('OfflineAreaService: Deleted world area directory: ${area.directory}');
        }
        _areas.remove(area);
      }
      
      await saveAreasToDisk();
      debugPrint('OfflineAreaService: Legacy world area cleanup complete');
    }
  }

}

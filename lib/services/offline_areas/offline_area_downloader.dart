import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:collection/collection.dart';

import '../../app_state.dart';
import '../../models/osm_camera_node.dart';
import '../../models/tile_provider.dart';
import '../map_data_provider.dart';
import '../map_data_submodules/tiles_from_remote.dart';
import 'offline_area_models.dart';
import 'offline_tile_utils.dart';
import 'package:flock_map_app/dev_config.dart';

/// Handles the actual downloading process for offline areas
class OfflineAreaDownloader {
  static const int _maxRetryPasses = 3;

  /// Download tiles and cameras for an offline area
  static Future<bool> downloadArea({
    required OfflineArea area,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String directory,
    void Function(double progress)? onProgress,
    required Future<void> Function() saveAreasToDisk,
    required Future<void> Function(OfflineArea) getAreaSizeBytes,
  }) async {
    // Get tile provider info from the area metadata or current AppState
    TileProvider? tileProvider;
    TileType? tileType;
    
    final appState = AppState.instance;
    
    if (area.tileProviderId != null && area.tileTypeId != null) {
      // Use the provider info stored with the area (for refreshing existing areas)
      try {
        tileProvider = appState.tileProviders.firstWhere(
          (p) => p.id == area.tileProviderId,
        );
        tileType = tileProvider.tileTypes.firstWhere(
          (t) => t.id == area.tileTypeId,
        );
      } catch (e) {
        // Fallback if stored provider/type not found
        tileProvider = appState.selectedTileProvider ?? appState.tileProviders.firstOrNull;
        tileType = appState.selectedTileType ?? tileProvider?.tileTypes.firstOrNull;
      }
    } else {
      // New area - use currently selected provider
      tileProvider = appState.selectedTileProvider ?? appState.tileProviders.firstOrNull;
      tileType = appState.selectedTileType ?? tileProvider?.tileTypes.firstOrNull;
    }
    // Calculate tiles to download
    Set<List<int>> allTiles;
    if (area.isPermanent) {
      allTiles = computeTileList(globalWorldBounds(), kWorldMinZoom, kWorldMaxZoom);
    } else {
      allTiles = computeTileList(bounds, minZoom, maxZoom);
    }
    area.tilesTotal = allTiles.length;

    // Download tiles with retry logic
    final success = await _downloadTilesWithRetry(
      area: area,
      allTiles: allTiles,
      directory: directory,
      onProgress: onProgress,
      saveAreasToDisk: saveAreasToDisk,
      getAreaSizeBytes: getAreaSizeBytes,
      tileProvider: tileProvider,
      tileType: tileType,
    );

    // Download cameras for non-permanent areas
    if (!area.isPermanent) {
      await _downloadCameras(
        area: area,
        bounds: bounds,
        minZoom: minZoom,
        directory: directory,
      );
    } else {
      area.cameras = [];
    }

    return success;
  }

  /// Download tiles with retry logic
  static Future<bool> _downloadTilesWithRetry({
    required OfflineArea area,
    required Set<List<int>> allTiles,
    required String directory,
    void Function(double progress)? onProgress,
    required Future<void> Function() saveAreasToDisk,
    required Future<void> Function(OfflineArea) getAreaSizeBytes,
    TileProvider? tileProvider,
    TileType? tileType,
  }) async {
    int pass = 0;
    Set<List<int>> tilesToFetch = allTiles;
    int totalDone = 0;

    while (pass < _maxRetryPasses && tilesToFetch.isNotEmpty) {
      pass++;
      debugPrint('DownloadArea: pass #$pass for area ${area.id}. Need ${tilesToFetch.length} tiles.');
      
      for (final tile in tilesToFetch) {
        if (area.status == OfflineAreaStatus.cancelled) break;
        
        if (await _downloadSingleTile(tile, directory, area, tileProvider, tileType)) {
          totalDone++;
          area.tilesDownloaded = totalDone;
          area.progress = area.tilesTotal == 0 ? 0.0 : (totalDone / area.tilesTotal);
          onProgress?.call(area.progress);
        }
      }

      await getAreaSizeBytes(area);
      await saveAreasToDisk();
      
      // Check for missing tiles
      tilesToFetch = _findMissingTiles(allTiles, directory);
      if (tilesToFetch.isEmpty) {
        return true; // Success!
      }
    }

    return false; // Failed after max retries
  }

  /// Download a single tile
  static Future<bool> _downloadSingleTile(
    List<int> tile, 
    String directory, 
    OfflineArea area,
    TileProvider? tileProvider,
    TileType? tileType,
  ) async {
    try {
      List<int> bytes;
      
      if (tileType != null && tileProvider != null) {
        // Use the same path as live tiles: build URL and fetch directly
        final tileUrl = tileType.getTileUrl(tile[0], tile[1], tile[2], apiKey: tileProvider.apiKey);
        bytes = await fetchRemoteTile(z: tile[0], x: tile[1], y: tile[2], url: tileUrl);
      } else {
        // Fallback to OSM for legacy areas or when no provider info
        bytes = await fetchOSMTile(z: tile[0], x: tile[1], y: tile[2]);
      }
      if (bytes.isNotEmpty) {
        await OfflineAreaDownloader.saveTileBytes(tile[0], tile[1], tile[2], directory, bytes);
        return true;
      }
    } catch (e) {
      debugPrint("Tile download failed for z=${tile[0]}, x=${tile[1]}, y=${tile[2]}: $e");
    }
    return false;
  }

  /// Find tiles that are missing from disk
  static Set<List<int>> _findMissingTiles(Set<List<int>> allTiles, String directory) {
    final missingTiles = <List<int>>{};
    for (final tile in allTiles) {
      final file = File('$directory/tiles/${tile[0]}/${tile[1]}/${tile[2]}.png');
      if (!file.existsSync()) {
        missingTiles.add(tile);
      }
    }
    return missingTiles;
  }

  /// Download cameras for the area with expanded bounds
  static Future<void> _downloadCameras({
    required OfflineArea area,
    required LatLngBounds bounds,
    required int minZoom,
    required String directory,
  }) async {
    // Calculate expanded camera bounds that cover the entire tile area at minimum zoom
    final cameraBounds = _calculateCameraBounds(bounds, minZoom);
    final cameras = await MapDataProvider().getAllCamerasForDownload(
      bounds: cameraBounds,
      profiles: AppState.instance.enabledProfiles,
    );
    area.cameras = cameras;
    await OfflineAreaDownloader.saveCameras(cameras, directory);
    debugPrint('Area ${area.id}: Downloaded ${cameras.length} cameras from expanded bounds');
  }

  /// Calculate expanded bounds that cover the entire tile area at minimum zoom
  static LatLngBounds _calculateCameraBounds(LatLngBounds visibleBounds, int minZoom) {
    final tiles = computeTileList(visibleBounds, minZoom, minZoom);
    if (tiles.isEmpty) return visibleBounds;
    
    // Find the bounding box of all these tiles
    double minLat = 90.0, maxLat = -90.0;
    double minLon = 180.0, maxLon = -180.0;
    
    for (final tile in tiles) {
      final tileBounds = tileToLatLngBounds(tile[1], tile[2], tile[0]);
      
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

  /// Save tile bytes to disk
  static Future<void> saveTileBytes(int z, int x, int y, String baseDir, List<int> bytes) async {
    final dir = Directory('$baseDir/tiles/$z/$x');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$y.png');
    await file.writeAsBytes(bytes);
  }

  /// Save cameras to disk as JSON
  static Future<void> saveCameras(List<OsmCameraNode> cams, String dir) async {
    final file = File('$dir/cameras.json');
    await file.writeAsString(jsonEncode(cams.map((c) => c.toJson()).toList()));
  }
}
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:path_provider/path_provider.dart';

import 'offline_area_models.dart';
import 'offline_tile_utils.dart';
import 'package:flock_map_app/dev_config.dart';

/// Manages the world area (permanent offline area for base map)
class WorldAreaManager {
  static const String _worldAreaId = 'world';
  static const String _worldAreaName = 'World Base Map';

  /// Ensure world area exists and check if download is needed
  static Future<OfflineArea> ensureWorldArea(
    List<OfflineArea> areas,
    Future<Directory> Function() getOfflineAreaDir,
    Future<void> Function({
      required String id,
      required LatLngBounds bounds,
      required int minZoom,
      required int maxZoom,
      required String directory,
      String? name,
      String? tileProviderId,
      String? tileProviderName,
      String? tileTypeId,
      String? tileTypeName,
    }) downloadArea,
  ) async {
    // Find existing world area
    OfflineArea? world;
    for (final area in areas) {
      if (area.isPermanent) {
        world = area;
        break;
      }
    }

    // Create world area if it doesn't exist, or update existing area without provider info
    if (world == null) {
      final appDocDir = await getOfflineAreaDir();
      final dir = "${appDocDir.path}/$_worldAreaId";
      world = OfflineArea(
        id: _worldAreaId,
        name: _worldAreaName,
        bounds: globalWorldBounds(),
        minZoom: kWorldMinZoom,
        maxZoom: kWorldMaxZoom,
        directory: dir,
        status: OfflineAreaStatus.downloading,
        isPermanent: true,
        // World area always uses OpenStreetMap
        tileProviderId: 'openstreetmap',
        tileProviderName: 'OpenStreetMap',
        tileTypeId: 'osm_street',
        tileTypeName: 'Street Map',
      );
      areas.insert(0, world);
    } else if (world.tileProviderId == null || world.tileTypeId == null) {
      // Update existing world area that lacks provider metadata
      final updatedWorld = OfflineArea(
        id: world.id,
        name: world.name,
        bounds: world.bounds,
        minZoom: world.minZoom,
        maxZoom: world.maxZoom,
        directory: world.directory,
        status: world.status,
        progress: world.progress,
        tilesDownloaded: world.tilesDownloaded,
        tilesTotal: world.tilesTotal,
        cameras: world.cameras,
        sizeBytes: world.sizeBytes,
        isPermanent: world.isPermanent,
        // Add missing provider metadata
        tileProviderId: 'openstreetmap',
        tileProviderName: 'OpenStreetMap',
        tileTypeId: 'osm_street',
        tileTypeName: 'Street Map',
      );
      final index = areas.indexOf(world);
      areas[index] = updatedWorld;
      world = updatedWorld;
    }

    // Check world area status and start download if needed
    await _checkAndStartWorldDownload(world, downloadArea);
    return world;
  }

  /// Check world area download status and start if needed
  static Future<void> _checkAndStartWorldDownload(
    OfflineArea world,
    Future<void> Function({
      required String id,
      required LatLngBounds bounds,
      required int minZoom,
      required int maxZoom,
      required String directory,
      String? name,
      String? tileProviderId,
      String? tileProviderName,
      String? tileTypeId,
      String? tileTypeName,
    }) downloadArea,
  ) async {
    if (world.status == OfflineAreaStatus.complete) return;

    // Count existing tiles
    final expectedTiles = computeTileList(
      globalWorldBounds(), 
      kWorldMinZoom, 
      kWorldMaxZoom,
    );
    
    int filesFound = 0;
    for (final tile in expectedTiles) {
      final file = File('${world.directory}/tiles/${tile[0]}/${tile[1]}/${tile[2]}.png');
      if (file.existsSync()) {
        filesFound++;
      }
    }

    // Update world area stats
    world.tilesTotal = expectedTiles.length;
    world.tilesDownloaded = filesFound;
    world.progress = (world.tilesTotal == 0) ? 0.0 : (filesFound / world.tilesTotal);
    
    if (filesFound == world.tilesTotal) {
      world.status = OfflineAreaStatus.complete;
      debugPrint('WorldAreaManager: World area download already complete.');
    } else {
      world.status = OfflineAreaStatus.downloading;
      debugPrint('WorldAreaManager: Starting world area download. ${world.tilesDownloaded}/${world.tilesTotal} tiles found.');
      
      // Start download (fire and forget) - use OSM for world areas
      downloadArea(
        id: world.id,
        bounds: world.bounds,
        minZoom: world.minZoom,
        maxZoom: world.maxZoom,
        directory: world.directory,
        name: world.name,
        tileProviderId: 'openstreetmap',
        tileProviderName: 'OpenStreetMap',
        tileTypeId: 'osm_street',
        tileTypeName: 'Street Map',
      );
    }
  }
}
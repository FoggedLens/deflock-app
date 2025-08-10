import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../services/map_data_provider.dart';
import '../app_state.dart';

/// Singleton in-memory tile cache and async provider for custom tiles.
class TileProviderWithCache extends TileProvider {
  static final Map<String, Uint8List> _tileCache = {};
  static Map<String, Uint8List> get tileCache => _tileCache;
  final VoidCallback? onTileCacheUpdated;

  TileProviderWithCache({this.onTileCacheUpdated});

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options, {MapSource source = MapSource.auto}) {
    final key = '${coords.z}/${coords.x}/${coords.y}';
    if (_tileCache.containsKey(key)) {
      return MemoryImage(_tileCache[key]!);
    } else {
      _fetchAndCacheTile(coords, key, source: source);
      // Always return a placeholder until the real tile is cached, regardless of source/offline/online.
      return const AssetImage('assets/transparent_1x1.png');
    }
  }

  static void clearCache() {
    _tileCache.clear();
    print('[TileProviderWithCache] Tile cache cleared');
  }

  void _fetchAndCacheTile(TileCoordinates coords, String key, {MapSource source = MapSource.auto}) async {
    // Don't fire multiple fetches for the same tile simultaneously
    if (_tileCache.containsKey(key)) return;
    try {
      final bytes = await MapDataProvider().getTile(
        z: coords.z, x: coords.x, y: coords.y, source: source,
      );
      if (bytes.isNotEmpty) {
        _tileCache[key] = Uint8List.fromList(bytes);
        print('[TileProviderWithCache] Cached tile $key, bytes=${bytes.length}');
        if (onTileCacheUpdated != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) => onTileCacheUpdated!());
        }
      }
      // If bytes were empty, don't cache (will re-attempt next time)
    } catch (e) {
      print('[TileProviderWithCache] Error fetching tile $key: $e');
      // Do NOT cache a failed or empty tile! Placeholder tiles will be evicted on online transition.
    }
  }
}

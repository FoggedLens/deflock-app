import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/scheduler.dart';
import '../services/map_data_provider.dart';

/// Singleton in-memory tile cache and async provider for custom tiles.
class TileProviderWithCache extends TileProvider {
  static final Map<String, Uint8List> _tileCache = {};
  static Map<String, Uint8List> get tileCache => _tileCache;
  final VoidCallback? onTileCacheUpdated;

  TileProviderWithCache({this.onTileCacheUpdated});

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options) {
    final key = '${coords.z}/${coords.x}/${coords.y}';
    if (_tileCache.containsKey(key)) {
      return MemoryImage(_tileCache[key]!);
    } else {
      _fetchAndCacheTile(coords, key);
      // Return a transparent PNG until the tile is available.
      return const AssetImage('assets/transparent_1x1.png');
    }
  }

  void _fetchAndCacheTile(TileCoordinates coords, String key) async {
    // Don't fire multiple fetches for the same tile simultaneously
    if (_tileCache.containsKey(key)) return;
    try {
      final bytes = await MapDataProvider().getTile(z: coords.z, x: coords.x, y: coords.y);
      if (bytes.isNotEmpty) {
        _tileCache[key] = Uint8List.fromList(bytes);
        print('[TileProviderWithCache] Cached tile $key, bytes=${bytes.length}');
        if (onTileCacheUpdated != null) {
          SchedulerBinding.instance.addPostFrameCallback((_) => onTileCacheUpdated!());
        }
      }
    } catch (e) {
      print('[TileProviderWithCache] Error fetching tile $key: $e');
      // Optionally: fall back to a different asset, or record failures
    }
  }
}

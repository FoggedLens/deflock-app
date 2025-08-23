import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/map_data_provider.dart';

/// In-memory tile cache and async provider for custom tiles.
class TileProviderWithCache extends TileProvider with ChangeNotifier {
  static final Map<String, Uint8List> _tileCache = {};
  static Map<String, Uint8List> get tileCache => _tileCache;
  
  bool _disposed = false;

  TileProviderWithCache();
  
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  ImageProvider getImage(TileCoordinates coords, TileLayer options, {MapSource source = MapSource.auto}) {
    final key = '${coords.z}/${coords.x}/${coords.y}';
    
    if (_tileCache.containsKey(key)) {
      final bytes = _tileCache[key]!;
      return MemoryImage(bytes);
    } else {
      _fetchAndCacheTile(coords, key, source: source);
      // Always return a placeholder until the real tile is cached
      return const AssetImage('assets/transparent_1x1.png');
    }
  }

  static void clearCache() {
    _tileCache.clear();
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
        // Only notify listeners if not disposed
        if (!_disposed) {
          notifyListeners(); // This updates any listening widgets
        }
      }
      // If bytes were empty, don't cache (will re-attempt next time)
    } catch (e) {
      // Do NOT cache a failed or empty tile! Placeholder tiles will be evicted on online transition.
    }
  }
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/map_data_provider.dart';
import '../services/map_data_submodules/tiles_from_osm.dart';

/// In-memory tile cache and async provider for custom tiles.
class TileProviderWithCache extends TileProvider with ChangeNotifier {
  static final Map<String, Uint8List> _tileCache = {};
  static Map<String, Uint8List> get tileCache => _tileCache;
  
  bool _disposed = false;
  int _disposeCount = 0;
  VoidCallback? _onTilesCachedCallback;
  
  TileProviderWithCache();
  
  /// Set a callback to be called when tiles are cached (used by MapView for refresh)
  void setOnTilesCachedCallback(VoidCallback? callback) {
    _onTilesCachedCallback = callback;
  }
  
  /// Cancel ALL pending tile requests - delegates to OSM tile fetcher
  void cancelAllTileRequests() {
    clearOSMTileQueue(); // This handles all the cancellation logic
    debugPrint('[TileProviderWithCache] Cancelled all tile requests');
  }
  
  @override
  void dispose() {
    _disposeCount++;
    
    // If already disposed, just silently return (common during FlutterMap rebuilds)
    if (_disposed) {
      debugPrint('[TileProviderWithCache] Already disposed (call #$_disposeCount) - ignoring');
      return;
    }
    
    debugPrint('[TileProviderWithCache] Disposing (call #$_disposeCount)');
    _disposed = true;
    
    // Safely call super.dispose() with error handling
    try {
      super.dispose();
    } catch (e) {
      debugPrint('[TileProviderWithCache] Error during disposal: $e');
      // Continue execution - disposal errors shouldn't crash the app
    }
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
        // Only notify listeners if not disposed and still mounted
        if (!_disposed && hasListeners) {
          notifyListeners(); // This updates any listening widgets
        }
        // Trigger map refresh callback to force tile re-rendering  
        debugPrint('[TileProviderWithCache] Tile cached: $key, calling refresh callback');
        _onTilesCachedCallback?.call();
      }
      // If bytes were empty, don't cache (will re-attempt next time)
    } catch (e) {
      // Cancelled requests will throw exceptions from fetchOSMTile(), just ignore them
      if (e.toString().contains('cancelled')) {
        debugPrint('[TileProviderWithCache] Tile request was cancelled: $key');
      }
      // Don't cache failed tiles regardless of reason
    }
  }
}

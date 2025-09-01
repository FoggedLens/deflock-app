import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/tile_provider.dart' as models;
import '../../services/simple_tile_service.dart';

/// Manages tile layer creation, caching, and provider switching.
/// Handles tile HTTP client lifecycle and cache invalidation.
class TileLayerManager {
  late final SimpleTileHttpClient _tileHttpClient;
  int _mapRebuildKey = 0;
  String? _lastTileTypeId;
  bool? _lastOfflineMode;

  /// Get the current map rebuild key for cache busting
  int get mapRebuildKey => _mapRebuildKey;

  /// Initialize the tile layer manager
  void initialize() {
    _tileHttpClient = SimpleTileHttpClient();
  }

  /// Dispose of resources
  void dispose() {
    _tileHttpClient.close();
  }

  /// Check if cache should be cleared and increment rebuild key if needed.
  /// Returns true if cache was cleared (map should be rebuilt).
  bool checkAndClearCacheIfNeeded({
    required String? currentTileTypeId,
    required bool currentOfflineMode,
  }) {
    bool shouldClear = false;
    String? reason;

    if ((_lastTileTypeId != null && _lastTileTypeId != currentTileTypeId)) {
      reason = 'tile type ($currentTileTypeId)';
      shouldClear = true;
    } else if ((_lastOfflineMode != null && _lastOfflineMode != currentOfflineMode)) {
      reason = 'offline mode ($currentOfflineMode)';
      shouldClear = true;
    }

    if (shouldClear) {
      // Force map rebuild with new key to bust flutter_map cache
      _mapRebuildKey++;
      debugPrint('[TileLayerManager] *** CACHE CLEAR *** $reason changed - rebuilding map $_mapRebuildKey');
    }

    _lastTileTypeId = currentTileTypeId;
    _lastOfflineMode = currentOfflineMode;

    return shouldClear;
  }

  /// Clear the tile request queue (call after cache clear)
  void clearTileQueue() {
    debugPrint('[TileLayerManager] Post-frame: Clearing tile request queue');
    _tileHttpClient.clearTileQueue();
  }

  /// Clear tile queue immediately (for zoom changes, etc.)
  void clearTileQueueImmediate() {
    _tileHttpClient.clearTileQueue();
  }

  /// Build tile layer widget with current provider and type.
  /// Uses fake domain that SimpleTileHttpClient can parse for cache separation.
  Widget buildTileLayer({
    required models.TileProvider? selectedProvider,
    required models.TileType? selectedTileType,
  }) {
    // Use fake domain with standard HTTPS scheme: https://tiles.local/provider/type/z/x/y
    // This naturally separates cache entries by provider and type while being HTTP-compatible
    final urlTemplate = 'https://tiles.local/${selectedProvider?.id ?? 'unknown'}/${selectedTileType?.id ?? 'unknown'}/{z}/{x}/{y}';
    
    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'me.deflock.deflockapp',
      tileProvider: NetworkTileProvider(
        httpClient: _tileHttpClient,
        // Enable flutter_map caching - cache busting handled by URL changes and FlutterMap key
      ),
    );
  }
}
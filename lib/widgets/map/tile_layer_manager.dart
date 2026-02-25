import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/tile_provider.dart' as models;
import '../../services/deflock_tile_provider.dart';

/// Manages tile layer creation, caching, and provider switching.
/// Uses DeFlock's custom tile provider for clean integration.
class TileLayerManager {
  DeflockTileProvider? _tileProvider;
  int _mapRebuildKey = 0;
  String? _lastTileTypeId;
  bool? _lastOfflineMode;

  /// Get the current map rebuild key for cache busting
  int get mapRebuildKey => _mapRebuildKey;

  /// Initialize the tile layer manager
  void initialize() {
    // Don't create tile provider here - create it fresh for each build
  }

  /// Dispose of resources
  void dispose() {
    _tileProvider?.dispose();
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
      // Dispose old provider before creating a fresh one (closes HTTP client)
      _tileProvider?.dispose();
      _tileProvider = null;
      debugPrint('[TileLayerManager] *** CACHE CLEAR *** $reason changed - rebuilding map $_mapRebuildKey');
    }

    _lastTileTypeId = currentTileTypeId;
    _lastOfflineMode = currentOfflineMode;

    return shouldClear;
  }

  /// Clear the tile request queue (call after cache clear)
  void clearTileQueue() {
    // With NetworkTileProvider, clearing is handled by FlutterMap's internal cache
    // We just need to increment the rebuild key to bust the cache
    _mapRebuildKey++;
    debugPrint('[TileLayerManager] Cache cleared - rebuilding map $_mapRebuildKey');
  }

  /// Clear tile queue immediately (for zoom changes, etc.)
  void clearTileQueueImmediate() {
    // No immediate clearing needed — NetworkTileProvider aborts obsolete requests
  }

  /// Clear only tiles that are no longer visible in the current bounds
  void clearStaleRequests({required LatLngBounds currentBounds}) {
    // No selective clearing needed — NetworkTileProvider aborts obsolete requests
  }

  /// Build tile layer widget with current provider and type.
  /// Uses DeFlock's custom tile provider for clean integration with our offline/online system.
  Widget buildTileLayer({
    required models.TileProvider? selectedProvider,
    required models.TileType? selectedTileType,
  }) {
    // Create a fresh tile provider instance if we don't have one or cache was cleared
    _tileProvider ??= DeflockTileProvider();

    // Use the actual urlTemplate from the selected tile type. Our getTileUrl()
    // override handles the real URL generation; flutter_map uses urlTemplate
    // internally for cache key generation.
    final urlTemplate = selectedTileType?.urlTemplate
        ?? '${selectedProvider?.id ?? 'unknown'}/${selectedTileType?.id ?? 'unknown'}/{z}/{x}/{y}';

    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'me.deflock.deflockapp',
      maxZoom: selectedTileType?.maxZoom.toDouble() ?? 18.0,
      tileProvider: _tileProvider!,
    );
  }
}

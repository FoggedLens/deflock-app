import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../models/tile_provider.dart' as models;
import '../../services/deflock_tile_provider.dart';
import '../../services/provider_tile_cache_manager.dart';

/// Manages tile layer creation with per-provider caching and provider switching.
///
/// Each tile provider/type combination gets its own [DeflockTileProvider]
/// instance with isolated caching (separate cache directory, configurable size
/// limit, and policy-driven TTL enforcement). Providers are created lazily on
/// first use and cached for instant switching.
class TileLayerManager {
  final Map<String, DeflockTileProvider> _providers = {};
  int _mapRebuildKey = 0;
  String? _lastTileTypeId;
  bool? _lastOfflineMode;

  /// Get the current map rebuild key for cache busting.
  int get mapRebuildKey => _mapRebuildKey;

  /// Initialize the tile layer manager.
  ///
  /// [ProviderTileCacheManager.init] is called in main() before any widgets
  /// build, so this is a no-op retained for API compatibility.
  void initialize() {
    // Cache directory is already resolved in main().
  }

  /// Dispose of all provider resources.
  ///
  /// Synchronous to match Flutter's [State.dispose] contract. Each provider's
  /// async cleanup (closing HTTP clients) runs in the background; errors are
  /// caught to avoid unhandled exceptions from dropped futures.
  void dispose() {
    for (final provider in _providers.values) {
      unawaited(provider.dispose().catchError(
        (Object e) => debugPrint('[TileLayerManager] Provider dispose error: $e'),
      ));
    }
    _providers.clear();
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
      // Force map rebuild with new key to bust flutter_map cache.
      // We don't dispose providers here — they're reusable across switches.
      _mapRebuildKey++;
      debugPrint('[TileLayerManager] *** CACHE CLEAR *** $reason changed - rebuilding map $_mapRebuildKey');
    }

    _lastTileTypeId = currentTileTypeId;
    _lastOfflineMode = currentOfflineMode;

    return shouldClear;
  }

  /// Clear the tile request queue (call after cache clear).
  void clearTileQueue() {
    _mapRebuildKey++;
    debugPrint('[TileLayerManager] Cache cleared - rebuilding map $_mapRebuildKey');
  }

  /// Clear tile queue immediately (for zoom changes, etc.)
  void clearTileQueueImmediate() {
    // No immediate clearing needed — NetworkTileProvider aborts obsolete requests
  }

  /// Clear only tiles that are no longer visible in the current bounds.
  void clearStaleRequests({required LatLngBounds currentBounds}) {
    // No selective clearing needed — NetworkTileProvider aborts obsolete requests
  }

  /// Build tile layer widget with current provider and type.
  ///
  /// Gets or creates a [DeflockTileProvider] for the given provider/type
  /// combination, each with its own isolated cache.
  Widget buildTileLayer({
    required models.TileProvider? selectedProvider,
    required models.TileType? selectedTileType,
  }) {
    final tileProvider = _getOrCreateProvider(
      selectedProvider: selectedProvider,
      selectedTileType: selectedTileType,
    );

    // Use the actual urlTemplate from the selected tile type. Our getTileUrl()
    // override handles the real URL generation; flutter_map uses urlTemplate
    // internally for cache key generation.
    final urlTemplate = selectedTileType?.urlTemplate
        ?? '${selectedProvider?.id ?? 'unknown'}/${selectedTileType?.id ?? 'unknown'}/{z}/{x}/{y}';

    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'me.deflock.deflockapp',
      maxZoom: selectedTileType?.maxZoom.toDouble() ?? 18.0,
      tileProvider: tileProvider,
    );
  }

  /// Get or create a [DeflockTileProvider] for the given provider/type.
  DeflockTileProvider _getOrCreateProvider({
    required models.TileProvider? selectedProvider,
    required models.TileType? selectedTileType,
  }) {
    if (selectedProvider == null || selectedTileType == null) {
      // No provider configured — return a fallback with default config.
      return _providers.putIfAbsent(
        '_fallback',
        () => DeflockTileProvider(
          providerId: 'unknown',
          tileType: models.TileType(
            id: 'unknown',
            name: 'Unknown',
            urlTemplate: 'unknown/unknown/{z}/{x}/{y}',
            attribution: '',
          ),
        ),
      );
    }

    final key = '${selectedProvider.id}/${selectedTileType.id}';
    return _providers.putIfAbsent(key, () {
      final cachingProvider = ProviderTileCacheManager.isInitialized
          ? ProviderTileCacheManager.getOrCreate(
              providerId: selectedProvider.id,
              tileTypeId: selectedTileType.id,
              policy: selectedTileType.servicePolicy,
            )
          : null;

      debugPrint(
        '[TileLayerManager] Creating provider for $key '
        '(cache: ${cachingProvider != null ? "enabled" : "disabled"})',
      );

      return DeflockTileProvider(
        providerId: selectedProvider.id,
        tileType: selectedTileType,
        apiKey: selectedProvider.apiKey,
        cachingProvider: cachingProvider,
      );
    });
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'provider_tile_cache_store.dart';
import 'service_policy.dart';

/// Factory and registry for per-provider [ProviderTileCacheStore] instances.
///
/// Creates cache stores under `{appCacheDir}/tile_cache/{providerId}/{tileTypeId}/`.
/// Call [init] once at startup (e.g., from TileLayerManager.initialize) to
/// resolve the platform cache directory. After init, [getOrCreate] is
/// synchronous — the cache store lazily creates its directory on first write.
class ProviderTileCacheManager {
  static final Map<String, ProviderTileCacheStore> _stores = {};
  static String? _baseCacheDir;

  /// Resolve the platform cache directory. Call once at startup.
  static Future<void> init() async {
    if (_baseCacheDir != null) return;
    final cacheDir = await getApplicationCacheDirectory();
    _baseCacheDir = p.join(cacheDir.path, 'tile_cache');
  }

  /// Whether the manager has been initialized.
  static bool get isInitialized => _baseCacheDir != null;

  /// Get or create a cache store for a specific provider/tile type combination.
  ///
  /// Synchronous after [init] has been called. The cache store lazily creates
  /// its directory on first write.
  static ProviderTileCacheStore getOrCreate({
    required String providerId,
    required String tileTypeId,
    required ServicePolicy policy,
    int? maxCacheBytes,
  }) {
    assert(_baseCacheDir != null,
        'ProviderTileCacheManager.init() must be called before getOrCreate()');

    final key = '$providerId/$tileTypeId';
    if (_stores.containsKey(key)) return _stores[key]!;

    final cacheDir = p.join(_baseCacheDir!, providerId, tileTypeId);

    final store = ProviderTileCacheStore(
      cacheDirectory: cacheDir,
      maxCacheBytes: maxCacheBytes ?? 500 * 1024 * 1024,
      overrideFreshAge: policy.minCacheTtl,
    );

    _stores[key] = store;
    return store;
  }

  /// Delete a specific provider's cache directory and remove the store.
  static Future<void> deleteCache(String providerId, String tileTypeId) async {
    final key = '$providerId/$tileTypeId';
    final store = _stores.remove(key);
    if (store != null) {
      await store.clear();
    } else if (_baseCacheDir != null) {
      final cacheDir = Directory(p.join(_baseCacheDir!, providerId, tileTypeId));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    }
  }

  /// Get estimated cache sizes for all active stores.
  ///
  /// Returns a map of `providerId/tileTypeId` → size in bytes.
  static Future<Map<String, int>> getCacheSizes() async {
    final sizes = <String, int>{};
    for (final entry in _stores.entries) {
      sizes[entry.key] = await entry.value.estimatedSizeBytes;
    }
    return sizes;
  }

  /// Remove a store from the registry (e.g., when a provider is disposed).
  static void unregister(String providerId, String tileTypeId) {
    _stores.remove('$providerId/$tileTypeId');
  }

  /// Clear all stores and reset the registry (for testing).
  @visibleForTesting
  static Future<void> resetAll() async {
    for (final store in _stores.values) {
      await store.clear();
    }
    _stores.clear();
    _baseCacheDir = null;
  }

  /// Set the base cache directory directly (for testing).
  @visibleForTesting
  static void setBaseCacheDir(String dir) {
    _baseCacheDir = dir;
  }
}

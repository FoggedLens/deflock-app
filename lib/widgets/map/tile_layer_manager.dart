import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../../models/tile_provider.dart' as models;
import '../../services/deflock_tile_provider.dart';
import '../../services/provider_tile_cache_manager.dart';
import '../../services/vector_style_service.dart';

/// Manages tile layer creation with per-provider caching and provider switching.
///
/// Each tile provider/type combination gets its own [DeflockTileProvider]
/// instance with isolated caching (separate cache directory, configurable size
/// limit, and policy-driven TTL enforcement). Providers are created lazily on
/// first use and cached for instant switching.
class TileLayerManager {
  final Map<String, DeflockTileProvider> _providers = {};
  int _mapRebuildKey = 0;
  String? _lastProviderId;
  String? _lastTileTypeId;
  bool? _lastOfflineMode;

  /// Keys currently being loaded to prevent duplicate async loads.
  final Set<String> _pendingStyleLoads = {};

  /// Fires when a vector style finishes loading asynchronously.
  /// Subscribers (e.g., MapView) call setState to trigger a rebuild.
  final StreamController<void> _styleLoadedController =
      StreamController<void>.broadcast();

  /// Stream that fires when a vector style has been loaded.
  Stream<void> get styleLoaded => _styleLoadedController.stream;

  /// Stream that triggers flutter_map to drop all tiles and reload.
  /// Fired after a debounced delay when tile errors are detected.
  final StreamController<void> _resetController =
      StreamController<void>.broadcast();

  /// Separate retry timers for raster and vector tile errors.
  Timer? _rasterRetryTimer;
  Timer? _vectorRetryTimer;

  /// Current retry delay — starts at [_minRetryDelay] and doubles on each
  /// retry cycle (capped at [_maxRetryDelay]).  Resets to [_minRetryDelay]
  /// when a tile loads successfully.
  Duration _retryDelay = const Duration(seconds: 2);

  static const _minRetryDelay = Duration(seconds: 2);
  static const _maxRetryDelay = Duration(seconds: 60);

  /// Get the current map rebuild key for cache busting.
  int get mapRebuildKey => _mapRebuildKey;

  /// Current retry delay (exposed for testing).
  @visibleForTesting
  Duration get retryDelay => _retryDelay;

  /// Stream of reset events (exposed for testing).
  @visibleForTesting
  Stream<void> get resetStream => _resetController.stream;

  /// Initialize the tile layer manager.
  ///
  /// [ProviderTileCacheManager.init] is called in main() before any widgets
  /// build, so this is a no-op retained for API compatibility.
  void initialize() {
    // Cache directory is already resolved in main().
  }

  /// Dispose of all provider resources.
  ///
  /// Synchronous to match Flutter's [State.dispose] contract. Calls
  /// [DeflockTileProvider.shutdown] to permanently close each provider's HTTP
  /// client.  (We don't call provider.dispose() here — flutter_map already
  /// called it when the TileLayer widget was removed, and it's safe to call
  /// again but unnecessary.)
  void dispose() {
    _rasterRetryTimer?.cancel();
    _vectorRetryTimer?.cancel();
    _resetController.close();
    _styleLoadedController.close();
    _pendingStyleLoads.clear();
    for (final provider in _providers.values) {
      provider.shutdown();
    }
    _providers.clear();
  }

  /// Check if cache should be cleared and increment rebuild key if needed.
  /// Returns true if cache was cleared (map should be rebuilt).
  bool checkAndClearCacheIfNeeded({
    required String? currentProviderId,
    required String? currentTileTypeId,
    required bool currentOfflineMode,
  }) {
    bool shouldClear = false;
    String? reason;

    if (_lastProviderId != currentProviderId) {
      reason = 'provider ($currentProviderId)';
      shouldClear = true;
    } else if (_lastTileTypeId != currentTileTypeId) {
      reason = 'tile type ($currentTileTypeId)';
      shouldClear = true;
    } else if (_lastOfflineMode != currentOfflineMode) {
      reason = 'offline mode ($currentOfflineMode)';
      shouldClear = true;
    }

    if (shouldClear) {
      // Force map rebuild with new key to bust flutter_map cache.
      // We don't dispose providers here — they're reusable across switches.
      _mapRebuildKey++;
      // Reset backoff so the new provider starts with a clean slate.
      // Cancel any pending retry timer — it belongs to the old provider's errors.
      _retryDelay = _minRetryDelay;
      _rasterRetryTimer?.cancel();
      _vectorRetryTimer?.cancel();
      debugPrint('[TileLayerManager] *** CACHE CLEAR *** $reason changed - rebuilding map $_mapRebuildKey');
    }

    _lastProviderId = currentProviderId;
    _lastTileTypeId = currentTileTypeId;
    _lastOfflineMode = currentOfflineMode;

    return shouldClear;
  }

  /// Clear the tile request queue (call after cache clear).
  ///
  /// In the old architecture this incremented [_mapRebuildKey] a second time
  /// to force a rebuild after the provider was disposed and recreated.  With
  /// per-provider caching, [checkAndClearCacheIfNeeded] already increments the
  /// key, so this is now a no-op.  Kept for API compatibility with map_view.
  void clearTileQueue() {
    // No-op: checkAndClearCacheIfNeeded() already incremented _mapRebuildKey.
  }

  /// Clear tile queue immediately (for zoom changes, etc.)
  void clearTileQueueImmediate() {
    // No immediate clearing needed — NetworkTileProvider aborts obsolete requests
  }

  /// Clear only tiles that are no longer visible in the current bounds.
  void clearStaleRequests({required LatLngBounds currentBounds}) {
    // No selective clearing needed — NetworkTileProvider aborts obsolete requests
  }

  /// Called by flutter_map when a tile fails to load.  Schedules a debounced
  /// reset so that all failed tiles get retried after the burst of errors
  /// settles down.  Uses exponential backoff: 2s → 4s → 8s → … → 60s cap.
  ///
  /// Skips retry for [TileLoadCancelledException] (tile scrolled off screen)
  /// and [TileNotAvailableOfflineException] (no cached data, retrying won't
  /// help without network).
  @visibleForTesting
  void onTileLoadError(
    TileImage tile,
    Object error,
    StackTrace? stackTrace,
  ) {
    // Cancelled tiles are already gone — no retry needed.
    if (error is TileLoadCancelledException) return;

    // Offline misses won't resolve by retrying — tile isn't cached.
    if (error is TileNotAvailableOfflineException) return;

    debugPrint(
      '[TileLayerManager] Tile error at '
      '${tile.coordinates.z}/${tile.coordinates.x}/${tile.coordinates.y}, '
      'scheduling retry in ${_retryDelay.inSeconds}s',
    );
    scheduleRetry();
  }

  /// Schedule a debounced tile reset with exponential backoff.
  @visibleForTesting
  void scheduleRetry() => _scheduleRetryOn(
        timer: _rasterRetryTimer,
        setTimer: (t) => _rasterRetryTimer = t,
        controller: _resetController,
        label: 'raster tile',
      );

  /// Schedule a delayed vector style retry with exponential backoff.
  void _scheduleVectorRetry() => _scheduleRetryOn(
        timer: _vectorRetryTimer,
        setTimer: (t) => _vectorRetryTimer = t,
        controller: _styleLoadedController,
        label: 'vector style',
        onFire: () => _mapRebuildKey++,
      );

  /// Shared retry helper: cancels [timer], fires [controller] after
  /// [_retryDelay], then doubles the delay (capped at [_maxRetryDelay]).
  void _scheduleRetryOn({
    required Timer? timer,
    required void Function(Timer) setTimer,
    required StreamController<void> controller,
    required String label,
    void Function()? onFire,
  }) {
    timer?.cancel();
    setTimer(Timer(_retryDelay, () {
      if (!controller.isClosed) {
        debugPrint('[TileLayerManager] Retrying $label (delay was ${_retryDelay.inSeconds}s)');
        onFire?.call();
        controller.add(null);
      }
      _retryDelay = Duration(
        milliseconds: min(
          _retryDelay.inMilliseconds * 2,
          _maxRetryDelay.inMilliseconds,
        ),
      );
    }));
  }

  /// Reset backoff to minimum delay.  Called when a tile loads successfully
  /// via the offline-first path, indicating connectivity has been restored.
  ///
  /// Note: the common path (`NetworkTileImageProvider`) does not call this,
  /// so backoff resets only when the offline-first path succeeds over the
  /// network.  In practice this is fine — the common path's `RetryClient`
  /// handles its own retries, and the reset stream only retries tiles that
  /// flutter_map has already marked as `loadError`.
  void onTileLoadSuccess() {
    _retryDelay = _minRetryDelay;
  }

  /// Build tile layer widget with current provider and type.
  ///
  /// Dispatches to [_buildRasterTileLayer] or [_buildVectorTileLayer]
  /// depending on [models.TileType.isVector].
  Widget buildTileLayer({
    required models.TileProvider? selectedProvider,
    required models.TileType? selectedTileType,
  }) {
    if (selectedTileType != null && selectedTileType.isVector) {
      return _buildVectorTileLayer(
        selectedProvider: selectedProvider,
        selectedTileType: selectedTileType,
      );
    }
    return _buildRasterTileLayer(
      selectedProvider: selectedProvider,
      selectedTileType: selectedTileType,
    );
  }

  /// Build a raster [TileLayer] (existing behavior).
  Widget _buildRasterTileLayer({
    required models.TileProvider? selectedProvider,
    required models.TileType? selectedTileType,
  }) {
    final tileProvider = _getOrCreateProvider(
      selectedProvider: selectedProvider,
      selectedTileType: selectedTileType,
    );

    final urlTemplate = selectedTileType?.urlTemplate
        ?? '${selectedProvider?.id ?? 'unknown'}/${selectedTileType?.id ?? 'unknown'}/{z}/{x}/{y}';

    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: 'me.deflock.deflockapp',
      maxZoom: selectedTileType?.maxZoom.toDouble() ?? 18.0,
      tileProvider: tileProvider,
      reset: _resetController.stream,
      errorTileCallback: onTileLoadError,
      evictErrorTileStrategy: EvictErrorTileStrategy.notVisible,
    );
  }

  /// Build a [VectorTileLayer] for vector style tile types.
  ///
  /// If the style is already cached, returns the layer immediately.
  /// Otherwise, triggers an async load and returns a placeholder; when the
  /// style loads, fires [styleLoaded] so the map can rebuild.
  Widget _buildVectorTileLayer({
    required models.TileProvider? selectedProvider,
    required models.TileType? selectedTileType,
  }) {
    if (selectedTileType == null || selectedTileType.styleUrl == null) {
      return const SizedBox.shrink();
    }

    final styleUrl = selectedTileType.styleUrl!;
    final apiKey = selectedProvider?.apiKey;
    final cached = VectorStyleService.instance.getCached(styleUrl, apiKey: apiKey);

    if (cached != null) {
      return VectorTileLayer(
        tileProviders: cached.providers,
        theme: cached.theme,
        sprites: cached.sprites,
        maximumZoom: selectedTileType.maxZoom.toDouble(),
        tileOffset: TileOffset.mapbox,
      );
    }

    // Style not loaded yet — trigger async load and return placeholder.
    _loadVectorStyleAsync(
      styleUrl: styleUrl,
      apiKey: apiKey,
    );

    return const SizedBox.shrink();
  }

  /// Asynchronously load a vector style via [VectorStyleService].
  void _loadVectorStyleAsync({
    required String styleUrl,
    String? apiKey,
  }) {
    final loadKey = '$styleUrl|${apiKey ?? ''}';
    // Already in flight — VectorStyleService deduplicates, but skip the callback wiring.
    if (_pendingStyleLoads.contains(loadKey)) return;
    _pendingStyleLoads.add(loadKey);

    VectorStyleService.instance
        .load(styleUrl, apiKey: apiKey)
        .then((_) {
      _pendingStyleLoads.remove(loadKey);
      if (!_styleLoadedController.isClosed) {
        _mapRebuildKey++;
        _styleLoadedController.add(null);
      }
    }).catchError((Object error) {
      _pendingStyleLoads.remove(loadKey);
      debugPrint('[TileLayerManager] Failed to load vector style: $error');
      _scheduleVectorRetry();
    });
  }

  /// Build a config fingerprint for drift detection.
  ///
  /// If any of these fields change (e.g. user edits the URL template or
  /// rotates an API key) the cached [DeflockTileProvider] must be replaced.
  static String _configFingerprint(
    models.TileProvider provider,
    models.TileType tileType,
  ) =>
      '${provider.id}/${tileType.id}'
      '|${tileType.urlTemplate}'
      '|${tileType.maxZoom}'
      '|${provider.apiKey ?? ''}';

  /// Get or create a [DeflockTileProvider] for the given provider/type.
  ///
  /// Providers are cached by `providerId/tileTypeId`.  If the effective config
  /// (URL template, max zoom, API key) has changed since the provider was
  /// created, the stale instance is shut down and replaced.
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
            urlTemplate: 'https://unknown.invalid/tiles/{z}/{x}/{y}',
            attribution: '',
          ),
        ),
      );
    }

    final key = '${selectedProvider.id}/${selectedTileType.id}';
    final fingerprint = _configFingerprint(selectedProvider, selectedTileType);

    // Check for config drift: if the provider exists but its config has
    // changed, shut down the stale instance so a fresh one is created below.
    final existing = _providers[key];
    if (existing != null && existing.configFingerprint != fingerprint) {
      debugPrint(
        '[TileLayerManager] Config changed for $key — replacing provider',
      );
      existing.shutdown();
      _providers.remove(key);
    }

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
        onNetworkSuccess: onTileLoadSuccess,
        configFingerprint: fingerprint,
      );
    });
  }
}

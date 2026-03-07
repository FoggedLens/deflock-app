import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

import '../app_state.dart';
import '../models/tile_provider.dart' as models;
import 'http_client.dart';
import 'map_data_submodules/tiles_from_local.dart';
import 'offline_area_service.dart';

/// Thrown when a tile load is cancelled (tile scrolled off screen).
/// TileLayerManager skips retry for these — the tile is already gone.
class TileLoadCancelledException implements Exception {
  const TileLoadCancelledException();
}

/// Thrown when a tile is not available offline (no offline area or cache hit).
/// TileLayerManager skips retry for these — retrying won't help without network.
class TileNotAvailableOfflineException implements Exception {
  const TileNotAvailableOfflineException();
}

/// Custom tile provider that extends NetworkTileProvider to leverage its
/// built-in disk cache, RetryClient, ETag revalidation, and abort support,
/// while routing URLs through our TileType logic and supporting offline tiles.
///
/// Each instance is configured for a specific tile provider/type combination
/// with frozen config — no AppState lookups at request time (except for the
/// global offlineMode toggle).
///
/// Two runtime paths:
/// 1. **Common path** (no offline areas for current provider): delegates to
///    super.getImageWithCancelLoadingSupport() — full NetworkTileImageProvider
///    pipeline (disk cache, ETag revalidation, RetryClient, abort support).
/// 2. **Offline-first path** (has offline areas or offline mode): returns
///    DeflockOfflineTileImageProvider — checks disk cache and local tiles
///    first, falls back to HTTP via shared RetryClient on miss.
class DeflockTileProvider extends NetworkTileProvider {
  /// The shared HTTP client we own. We keep a reference because
  /// NetworkTileProvider._httpClient is private and _isInternallyCreatedClient
  /// will be false (we passed it in), so super.dispose() won't close it.
  final Client _sharedHttpClient;

  /// Frozen config for this provider instance.
  final String providerId;
  final models.TileType tileType;
  final String? apiKey;

  /// Opaque fingerprint of the config this provider was created with.
  /// Used by [TileLayerManager] to detect config drift after edits.
  final String configFingerprint;

  /// Caching provider for the offline-first path. The same instance is passed
  /// to super for the common path — we keep a reference here so we can also
  /// use it in [DeflockOfflineTileImageProvider].
  final MapCachingProvider? _cachingProvider;

  /// Called when a tile loads successfully via the network in the offline-first
  /// path. Used by [TileLayerManager] to reset exponential backoff.
  VoidCallback? onNetworkSuccess;

  // ignore: use_super_parameters
  DeflockTileProvider._({
    required Client httpClient,
    required this.providerId,
    required this.tileType,
    this.apiKey,
    MapCachingProvider? cachingProvider,
    this.onNetworkSuccess,
    this.configFingerprint = '',
  })  : _sharedHttpClient = httpClient,
        _cachingProvider = cachingProvider,
        super(
          httpClient: httpClient,
          cachingProvider: cachingProvider,
          // Let errors propagate so flutter_map marks tiles as failed
          // (loadError = true) rather than caching transparent images as
          // "successfully loaded". The TileLayerManager wires a reset stream
          // that retries failed tiles after a debounced delay.
          silenceExceptions: false,
        );

  factory DeflockTileProvider({
    required String providerId,
    required models.TileType tileType,
    String? apiKey,
    MapCachingProvider? cachingProvider,
    VoidCallback? onNetworkSuccess,
    String configFingerprint = '',
  }) {
    final client = UserAgentClient(RetryClient(Client()));
    return DeflockTileProvider._(
      httpClient: client,
      providerId: providerId,
      tileType: tileType,
      apiKey: apiKey,
      cachingProvider: cachingProvider,
      onNetworkSuccess: onNetworkSuccess,
      configFingerprint: configFingerprint,
    );
  }

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) {
    return tileType.getTileUrl(
      coordinates.z,
      coordinates.x,
      coordinates.y,
      apiKey: apiKey,
    );
  }

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    if (!_shouldCheckOfflineCache(coordinates.z)) {
      // Common path: no offline areas — delegate to NetworkTileProvider's
      // full pipeline (disk cache, ETag, RetryClient, abort support).
      return super.getImageWithCancelLoadingSupport(
        coordinates,
        options,
        cancelLoading,
      );
    }

    // Offline-first path: check local tiles first, fall back to network.
    return DeflockOfflineTileImageProvider(
      coordinates: coordinates,
      options: options,
      httpClient: _sharedHttpClient,
      headers: headers,
      cancelLoading: cancelLoading,
      isOfflineOnly: AppState.instance.offlineMode,
      providerId: providerId,
      tileTypeId: tileType.id,
      tileUrl: getTileUrl(coordinates, options),
      cachingProvider: _cachingProvider,
      onNetworkSuccess: onNetworkSuccess,
    );
  }

  /// Determine if we should check offline cache for this tile request.
  /// Only returns true if:
  /// 1. We're in offline mode (forced), OR
  /// 2. We have offline areas for the current provider/type
  ///
  /// This avoids the offline-first path (and its filesystem searches) when
  /// browsing online with providers that have no offline areas.
  bool _shouldCheckOfflineCache(int zoom) {
    // Always use offline path in offline mode
    if (AppState.instance.offlineMode) {
      return true;
    }

    // For online mode, only use offline path if we have relevant offline data
    // at this zoom level — tiles outside any area's zoom range go through the
    // common NetworkTileProvider path for better performance.
    final offlineService = OfflineAreaService();
    return offlineService.hasOfflineAreasForProviderAtZoom(
      providerId,
      tileType.id,
      zoom,
    );
  }

  @override
  Future<void> dispose() async {
    // Only call super — do NOT close _sharedHttpClient here.
    // flutter_map calls dispose() whenever the TileLayer widget is recycled
    // (e.g. provider switch causes a new FlutterMap key), but
    // TileLayerManager caches and reuses provider instances across switches.
    // Closing the HTTP client here would leave the cached instance broken —
    // all future tile requests would fail with "Client closed".
    //
    // Since we passed our own httpClient to NetworkTileProvider,
    // _isInternallyCreatedClient is false, so super.dispose() won't close it
    // either.  The client is closed in [shutdown], called by
    // TileLayerManager.dispose() when the map is truly torn down.
    await super.dispose();
  }

  /// Permanently close the HTTP client.  Called by [TileLayerManager.dispose]
  /// when the map widget is being torn down — NOT by flutter_map's widget
  /// recycling.
  void shutdown() {
    _sharedHttpClient.close();
  }
}

/// Image provider for the offline-first path.
///
/// Checks disk cache and offline areas before falling back to the network.
/// Caches successful network fetches to disk so panning back doesn't re-fetch.
/// On cancellation, lets in-flight downloads complete and caches the result
/// (fire-and-forget) instead of discarding downloaded bytes.
///
/// **Online mode flow:**
/// 1. Disk cache (fast hash-based file read) → hit + fresh → return
/// 2. Offline areas (file scan) → hit → return
/// 3. Network fetch with conditional headers from stale cache entry
/// 4. On cancel → fire-and-forget cache write for the in-flight download
/// 5. On 304 → return stale cached bytes, update cache metadata
/// 6. On 200 → cache to disk, decode and return
/// 7. On error → throw (flutter_map marks tile as failed)
///
/// **Offline mode flow:**
/// 1. Offline areas (primary source — guaranteed available)
/// 2. Disk cache (tiles cached from previous online sessions)
/// 3. Throw if both miss (flutter_map marks tile as failed)
class DeflockOfflineTileImageProvider
    extends ImageProvider<DeflockOfflineTileImageProvider> {
  final TileCoordinates coordinates;
  final TileLayer options;
  final Client httpClient;
  final Map<String, String> headers;
  final Future<void> cancelLoading;
  final bool isOfflineOnly;
  final String providerId;
  final String tileTypeId;
  final String tileUrl;
  final MapCachingProvider? cachingProvider;
  final VoidCallback? onNetworkSuccess;

  const DeflockOfflineTileImageProvider({
    required this.coordinates,
    required this.options,
    required this.httpClient,
    required this.headers,
    required this.cancelLoading,
    required this.isOfflineOnly,
    required this.providerId,
    required this.tileTypeId,
    required this.tileUrl,
    this.cachingProvider,
    this.onNetworkSuccess,
  });

  @override
  Future<DeflockOfflineTileImageProvider> obtainKey(
      ImageConfiguration configuration) {
    return SynchronousFuture<DeflockOfflineTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
      DeflockOfflineTileImageProvider key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      // Chain whenComplete into the codec future so there's a single future
      // for MultiFrameImageStreamCompleter to handle. Without this, the
      // whenComplete creates an orphaned future whose errors go unhandled.
      codec: _loadAsync(key, decode, chunkEvents).whenComplete(() {
        chunkEvents.close();
      }),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
    );
  }

  /// Try to read a tile from the disk cache. Returns null on miss or error.
  Future<CachedMapTile?> _getCachedTile() async {
    if (cachingProvider == null || !cachingProvider!.isSupported) return null;
    try {
      return await cachingProvider!.getTile(tileUrl);
    } on CachedMapTileReadFailure {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Write a tile to the disk cache (best-effort, never throws).
  void _putCachedTile({
    required Map<String, String> responseHeaders,
    Uint8List? bytes,
  }) {
    if (cachingProvider == null || !cachingProvider!.isSupported) return;
    try {
      final metadata = CachedMapTileMetadata.fromHttpHeaders(responseHeaders);
      cachingProvider!
          .putTile(url: tileUrl, metadata: metadata, bytes: bytes)
          .catchError((_) {});
    } catch (_) {
      // Best-effort: never fail the tile load due to cache write errors.
    }
  }

  Future<Codec> _loadAsync(
    DeflockOfflineTileImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    Future<Codec> decodeBytes(Uint8List bytes) =>
        ImmutableBuffer.fromUint8List(bytes).then(decode);

    // Track cancellation synchronously via Completer so the catch block
    // can reliably check it without microtask ordering races.
    final cancelled = Completer<void>();
    cancelLoading.then((_) {
      if (!cancelled.isCompleted) cancelled.complete();
    }).ignore();

    try {
      if (isOfflineOnly) {
        return await _loadOffline(decodeBytes, cancelled);
      }
      return await _loadOnline(decodeBytes, cancelled);
    } catch (e) {
      // Cancelled tiles throw — flutter_map handles the error silently.
      // Preserve TileNotAvailableOfflineException even if the tile was also
      // cancelled — it has distinct semantics (genuine cache miss) that
      // matter for diagnostics and future UI indicators.
      if (cancelled.isCompleted && e is! TileNotAvailableOfflineException) {
        throw const TileLoadCancelledException();
      }

      // Let real errors propagate so flutter_map marks loadError = true
      rethrow;
    }
  }

  /// Online mode: disk cache → offline areas → network (with caching).
  Future<Codec> _loadOnline(
    Future<Codec> Function(Uint8List) decodeBytes,
    Completer<void> cancelled,
  ) async {
    // 1. Check disk cache — fast hash-based file read.
    final cachedTile = await _getCachedTile();
    if (cachedTile != null && !cachedTile.metadata.isStale) {
      return await decodeBytes(cachedTile.bytes);
    }

    // 2. Check offline areas — file scan per area.
    try {
      final localBytes = await fetchLocalTile(
        z: coordinates.z,
        x: coordinates.x,
        y: coordinates.y,
        providerId: providerId,
        tileTypeId: tileTypeId,
      );
      return await decodeBytes(Uint8List.fromList(localBytes));
    } catch (_) {
      // Local miss — fall through to network
    }

    // 3. If cancelled before network, bail.
    if (cancelled.isCompleted) throw const TileLoadCancelledException();

    // 4. Network fetch with conditional headers from stale cache entry.
    final request = Request('GET', Uri.parse(tileUrl));
    request.headers.addAll(headers);
    if (cachedTile != null) {
      if (cachedTile.metadata.lastModified case final lastModified?) {
        request.headers[HttpHeaders.ifModifiedSinceHeader] =
            HttpDate.format(lastModified);
      }
      if (cachedTile.metadata.etag case final etag?) {
        request.headers[HttpHeaders.ifNoneMatchHeader] = etag;
      }
    }

    // 5. Race the download against cancelLoading.
    final networkFuture = httpClient.send(request).then((response) async {
      final bytes = await response.stream.toBytes();
      return (
        statusCode: response.statusCode,
        bytes: bytes,
        headers: response.headers,
      );
    });

    final result = await Future.any([
      networkFuture,
      cancelLoading.then((_) => (
            statusCode: 0,
            bytes: Uint8List(0),
            headers: <String, String>{},
          )),
    ]);

    // 6. On cancel — fire-and-forget cache write for the in-flight download
    // instead of discarding the downloaded bytes.
    if (cancelled.isCompleted || result.statusCode == 0) {
      networkFuture.then((r) {
        if (r.statusCode == 200 && r.bytes.isNotEmpty) {
          _putCachedTile(responseHeaders: r.headers, bytes: r.bytes);
        }
      }).ignore();
      throw const TileLoadCancelledException();
    }

    // 7. On 304 Not Modified → return stale cached bytes, update metadata.
    if (result.statusCode == HttpStatus.notModified && cachedTile != null) {
      _putCachedTile(responseHeaders: result.headers);
      onNetworkSuccess?.call();
      return await decodeBytes(cachedTile.bytes);
    }

    // 8. On 200 OK → cache to disk, decode and return.
    if (result.statusCode == 200 && result.bytes.isNotEmpty) {
      _putCachedTile(responseHeaders: result.headers, bytes: result.bytes);
      onNetworkSuccess?.call();
      return await decodeBytes(result.bytes);
    }

    // 9. Network error — throw so flutter_map marks the tile as failed.
    // Don't include tileUrl in the exception — it may contain API keys.
    throw HttpException(
      'Tile ${coordinates.z}/${coordinates.x}/${coordinates.y} '
      'returned status ${result.statusCode}',
    );
  }

  /// Offline mode: offline areas → disk cache → throw.
  Future<Codec> _loadOffline(
    Future<Codec> Function(Uint8List) decodeBytes,
    Completer<void> cancelled,
  ) async {
    // 1. Check offline areas (primary source — guaranteed available).
    try {
      final localBytes = await fetchLocalTile(
        z: coordinates.z,
        x: coordinates.x,
        y: coordinates.y,
        providerId: providerId,
        tileTypeId: tileTypeId,
      );
      if (cancelled.isCompleted) throw const TileLoadCancelledException();
      return await decodeBytes(Uint8List.fromList(localBytes));
    } on TileLoadCancelledException {
      rethrow;
    } catch (_) {
      // Local miss — fall through to disk cache
    }

    // 2. Check disk cache (tiles cached from previous online sessions).
    if (cancelled.isCompleted) throw const TileLoadCancelledException();
    final cachedTile = await _getCachedTile();
    if (cachedTile != null) {
      return await decodeBytes(cachedTile.bytes);
    }

    // 3. Both miss — throw so flutter_map marks the tile as failed.
    throw const TileNotAvailableOfflineException();
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is DeflockOfflineTileImageProvider &&
        other.coordinates == coordinates &&
        other.providerId == providerId &&
        other.tileTypeId == tileTypeId &&
        other.isOfflineOnly == isOfflineOnly;
  }

  @override
  int get hashCode =>
      Object.hash(coordinates, providerId, tileTypeId, isOfflineOnly);
}

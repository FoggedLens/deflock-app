import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart';
import 'package:http/retry.dart';

import '../app_state.dart';
import 'http_client.dart';
import 'map_data_submodules/tiles_from_local.dart';
import 'offline_area_service.dart';

/// Custom tile provider that extends NetworkTileProvider to leverage its
/// built-in disk cache, RetryClient, ETag revalidation, and abort support,
/// while routing URLs through our TileType logic and supporting offline tiles.
///
/// Two runtime paths:
/// 1. **Common path** (no offline areas for current provider): delegates to
///    super.getImageWithCancelLoadingSupport() — full NetworkTileImageProvider
///    pipeline (disk cache, ETag revalidation, RetryClient, abort support).
/// 2. **Offline-first path** (has offline areas or offline mode): returns
///    DeflockOfflineTileImageProvider — checks fetchLocalTile() first, falls
///    back to HTTP via shared RetryClient on miss.
class DeflockTileProvider extends NetworkTileProvider {
  /// The shared HTTP client we own. We keep a reference because
  /// NetworkTileProvider._httpClient is private and _isInternallyCreatedClient
  /// will be false (we passed it in), so super.dispose() won't close it.
  final Client _sharedHttpClient;

  DeflockTileProvider._({required Client httpClient})
      : _sharedHttpClient = httpClient,
        super(
          httpClient: httpClient,
          // Let errors propagate so flutter_map marks tiles as failed
          // (loadError = true) rather than caching transparent images as
          // "successfully loaded". The TileLayerManager wires a reset stream
          // that retries failed tiles after a debounced delay.
          silenceExceptions: false,
        );

  factory DeflockTileProvider() {
    final client = UserAgentClient(RetryClient(Client()));
    return DeflockTileProvider._(httpClient: client);
  }

  @override
  String getTileUrl(TileCoordinates coordinates, TileLayer options) {
    final appState = AppState.instance;
    final selectedTileType = appState.selectedTileType;
    final selectedProvider = appState.selectedTileProvider;

    if (selectedTileType == null || selectedProvider == null) {
      // Fallback to base implementation if no provider configured
      return super.getTileUrl(coordinates, options);
    }

    return selectedTileType.getTileUrl(
      coordinates.z,
      coordinates.x,
      coordinates.y,
      apiKey: selectedProvider.apiKey,
    );
  }

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) {
    if (!_shouldCheckOfflineCache()) {
      // Common path: no offline areas — delegate to NetworkTileProvider's
      // full pipeline (disk cache, ETag, RetryClient, abort support).
      return super.getImageWithCancelLoadingSupport(
        coordinates,
        options,
        cancelLoading,
      );
    }

    // Offline-first path: check local tiles first, fall back to network.
    final appState = AppState.instance;
    final providerId = appState.selectedTileProvider?.id ?? 'unknown';
    final tileTypeId = appState.selectedTileType?.id ?? 'unknown';

    return DeflockOfflineTileImageProvider(
      coordinates: coordinates,
      options: options,
      httpClient: _sharedHttpClient,
      headers: headers,
      cancelLoading: cancelLoading,
      isOfflineOnly: appState.offlineMode,
      providerId: providerId,
      tileTypeId: tileTypeId,
      tileUrl: getTileUrl(coordinates, options),
    );
  }

  /// Determine if we should check offline cache for this tile request.
  /// Only returns true if:
  /// 1. We're in offline mode (forced), OR
  /// 2. We have offline areas for the current provider/type
  ///
  /// This avoids the offline-first path (and its filesystem searches) when
  /// browsing online with providers that have no offline areas.
  bool _shouldCheckOfflineCache() {
    final appState = AppState.instance;

    // Always use offline path in offline mode
    if (appState.offlineMode) {
      return true;
    }

    // For online mode, only use offline path if we have relevant offline data
    final currentProvider = appState.selectedTileProvider;
    final currentTileType = appState.selectedTileType;

    if (currentProvider == null || currentTileType == null) {
      return false;
    }

    final offlineService = OfflineAreaService();
    return offlineService.hasOfflineAreasForProvider(
      currentProvider.id,
      currentTileType.id,
    );
  }

  @override
  Future<void> dispose() async {
    try {
      await super.dispose();
    } finally {
      _sharedHttpClient.close();
    }
  }
}

/// Image provider for the offline-first path.
///
/// Tries fetchLocalTile() first. On miss (and if online), falls back to an
/// HTTP GET via the shared RetryClient. Returns transparent tiles only for
/// intentional cancellations and offline-only mode; throws on real network
/// errors so flutter_map marks the tile as failed and retries via reset.
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
    final codecFuture = _loadAsync(key, decode, chunkEvents);

    codecFuture.whenComplete(() {
      chunkEvents.close();
    });

    return MultiFrameImageStreamCompleter(
      codec: codecFuture,
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
    );
  }

  Future<Codec> _loadAsync(
    DeflockOfflineTileImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    Future<Codec> decodeBytes(Uint8List bytes) =>
        ImmutableBuffer.fromUint8List(bytes).then(decode);

    Future<Codec> transparent() =>
        decodeBytes(TileProvider.transparentImage);

    // Track cancellation synchronously via Completer so the catch block
    // can reliably check it without microtask ordering races.
    final cancelled = Completer<void>();
    cancelLoading.then((_) {
      if (!cancelled.isCompleted) cancelled.complete();
    }).ignore();

    try {
      // Try local tile first — pass captured IDs to avoid a race if the
      // user switches provider while this async load is in flight.
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
        // Local miss — fall through to network if online
      }

      if (cancelled.isCompleted) return await transparent();
      if (isOfflineOnly) return await transparent();

      // Fall back to network via shared RetryClient.
      // Race the download against cancelLoading so we stop waiting if the
      // tile is pruned mid-flight (the underlying TCP connection is cleaned
      // up naturally by the shared client).
      final request = Request('GET', Uri.parse(tileUrl));
      request.headers.addAll(headers);

      final networkFuture = httpClient.send(request).then((response) async {
        final bytes = await response.stream.toBytes();
        return (statusCode: response.statusCode, bytes: bytes);
      });

      final result = await Future.any([
        networkFuture,
        cancelLoading.then((_) => (statusCode: 0, bytes: Uint8List(0))),
      ]);

      // Cancelled / pruned — suppress any later error from the still-running
      // network future and return transparent (tile is being disposed anyway).
      if (cancelled.isCompleted || result.statusCode == 0) {
        networkFuture.ignore();
        return await transparent();
      }

      if (result.statusCode == 200 && result.bytes.isNotEmpty) {
        return await decodeBytes(result.bytes);
      }

      // Network error (non-200 or empty body) — throw so flutter_map marks
      // the tile as failed and the reset stream can trigger a retry.
      throw HttpException(
        'Tile ${coordinates.z}/${coordinates.x}/${coordinates.y} '
        'returned status ${result.statusCode}',
        uri: Uri.parse(tileUrl),
      );
    } catch (e) {
      // Cancelled tiles always get transparent (they're being disposed)
      if (cancelled.isCompleted) return await transparent();

      // Let real errors propagate so flutter_map marks loadError = true
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is DeflockOfflineTileImageProvider &&
        other.coordinates == coordinates &&
        other.providerId == providerId &&
        other.tileTypeId == tileTypeId;
  }

  @override
  int get hashCode => Object.hash(coordinates, providerId, tileTypeId);
}

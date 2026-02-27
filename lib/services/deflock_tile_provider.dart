import 'dart:async';
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
///    DeflockOfflineTileImageProvider — checks fetchLocalTile() first, falls
///    back to HTTP via shared RetryClient on miss.
class DeflockTileProvider extends NetworkTileProvider {
  /// The shared HTTP client we own. We keep a reference because
  /// NetworkTileProvider._httpClient is private and _isInternallyCreatedClient
  /// will be false (we passed it in), so super.dispose() won't close it.
  final Client _sharedHttpClient;

  /// Frozen config for this provider instance.
  final String providerId;
  final models.TileType tileType;
  final String? apiKey;

  DeflockTileProvider._({
    required Client httpClient,
    required this.providerId,
    required this.tileType,
    this.apiKey,
    super.cachingProvider,
  })  : _sharedHttpClient = httpClient,
        super(
          httpClient: httpClient,
          silenceExceptions: true,
        );

  factory DeflockTileProvider({
    required String providerId,
    required models.TileType tileType,
    String? apiKey,
    MapCachingProvider? cachingProvider,
  }) {
    final client = UserAgentClient(RetryClient(Client()));
    return DeflockTileProvider._(
      httpClient: client,
      providerId: providerId,
      tileType: tileType,
      apiKey: apiKey,
      cachingProvider: cachingProvider,
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
    // Always use offline path in offline mode
    if (AppState.instance.offlineMode) {
      return true;
    }

    // For online mode, only use offline path if we have relevant offline data
    final offlineService = OfflineAreaService();
    return offlineService.hasOfflineAreasForProvider(
      providerId,
      tileType.id,
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
/// HTTP GET via the shared RetryClient. Handles cancelLoading abort and
/// returns transparent tiles on errors (consistent with silenceExceptions).
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

    try {
      // Track cancellation
      bool cancelled = false;
      cancelLoading.then((_) => cancelled = true);

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

      if (cancelled) return await transparent();
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

      if (cancelled || result.statusCode == 0) return await transparent();

      if (result.statusCode == 200 && result.bytes.isNotEmpty) {
        return await decodeBytes(result.bytes);
      }

      return await transparent();
    } catch (e) {
      // Don't log routine offline misses
      if (!e.toString().contains('offline')) {
        debugPrint(
            '[DeflockTileProvider] Offline-first tile failed '
            '${coordinates.z}/${coordinates.x}/${coordinates.y} '
            '(${e.runtimeType})');
      }
      return await ImmutableBuffer.fromUint8List(TileProvider.transparentImage)
          .then(decode);
    }
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

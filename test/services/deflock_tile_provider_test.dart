import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/models/tile_provider.dart' as models;
import 'package:deflockapp/services/deflock_tile_provider.dart';
import 'package:deflockapp/services/provider_tile_cache_store.dart';

class MockAppState extends Mock implements AppState {}
class MockMapCachingProvider extends Mock implements MapCachingProvider {}

void main() {
  late DeflockTileProvider provider;
  late MockAppState mockAppState;

  final osmTileType = models.TileType(
    id: 'osm_street',
    name: 'Street Map',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap',
    maxZoom: 19,
  );

  final mapboxTileType = models.TileType(
    id: 'mapbox_satellite',
    name: 'Satellite',
    urlTemplate:
        'https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90?access_token={api_key}',
    attribution: '© Mapbox',
  );

  setUp(() {
    mockAppState = MockAppState();
    AppState.instance = mockAppState;

    // Default stubs: online, no offline areas
    when(() => mockAppState.offlineMode).thenReturn(false);

    provider = DeflockTileProvider(
      providerId: 'openstreetmap',
      tileType: osmTileType,
    );
  });

  tearDown(() async {
    provider.shutdown();
    AppState.instance = MockAppState();
  });

  group('DeflockTileProvider', () {
    test('supportsCancelLoading is true', () {
      expect(provider.supportsCancelLoading, isTrue);
    });

    test('getTileUrl() uses frozen tileType config', () {
      const coords = TileCoordinates(1, 2, 3);
      final options = TileLayer(urlTemplate: 'ignored/{z}/{x}/{y}');

      final url = provider.getTileUrl(coords, options);

      expect(url, equals('https://tile.openstreetmap.org/3/1/2.png'));
    });

    test('getTileUrl() includes API key when present', () async {
      provider.shutdown();
      provider = DeflockTileProvider(
        providerId: 'mapbox',
        tileType: mapboxTileType,
        apiKey: 'test_key_123',
      );

      const coords = TileCoordinates(1, 2, 10);
      final options = TileLayer(urlTemplate: 'ignored');

      final url = provider.getTileUrl(coords, options);

      expect(url, contains('access_token=test_key_123'));
      expect(url, contains('/10/1/2@2x'));
    });

    test('routes to network path when no offline areas exist', () {
      // offlineMode = false, OfflineAreaService not initialized → no offline areas
      const coords = TileCoordinates(5, 10, 12);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancelLoading = Future<void>.value();

      final imageProvider = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        cancelLoading,
      );

      // Should NOT be a DeflockOfflineTileImageProvider — it should be the
      // NetworkTileImageProvider returned by super
      expect(imageProvider, isNot(isA<DeflockOfflineTileImageProvider>()));
    });

    test('routes to offline path when offline mode is enabled', () {
      when(() => mockAppState.offlineMode).thenReturn(true);

      const coords = TileCoordinates(5, 10, 12);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancelLoading = Future<void>.value();

      final imageProvider = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        cancelLoading,
      );

      expect(imageProvider, isA<DeflockOfflineTileImageProvider>());
      final offlineProvider = imageProvider as DeflockOfflineTileImageProvider;
      expect(offlineProvider.isOfflineOnly, isTrue);
      expect(offlineProvider.coordinates, equals(coords));
      expect(offlineProvider.providerId, equals('openstreetmap'));
      expect(offlineProvider.tileTypeId, equals('osm_street'));
    });

    test('frozen config is independent of AppState', () {
      // Provider was created with OSM config — changing AppState should not affect it
      const coords = TileCoordinates(1, 2, 3);
      final options = TileLayer(urlTemplate: 'ignored/{z}/{x}/{y}');

      final url = provider.getTileUrl(coords, options);
      expect(url, equals('https://tile.openstreetmap.org/3/1/2.png'));
    });
  });

  group('DeflockOfflineTileImageProvider', () {
    test('equal for same coordinates, provider/type, and offlineOnly', () {
      const coords = TileCoordinates(1, 2, 3);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancel = Future<void>.value();

      final a = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'https://example.com/3/1/2',
      );
      final b = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'https://other.com/3/1/2', // different — but not in ==
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal for different isOfflineOnly', () {
      const coords = TileCoordinates(1, 2, 3);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancel = Future<void>.value();

      final online = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'url',
      );
      final offline = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: true,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'url',
      );

      expect(online, isNot(equals(offline)));
    });

    test('not equal for different coordinates', () {
      const coords1 = TileCoordinates(1, 2, 3);
      const coords2 = TileCoordinates(1, 2, 4);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancel = Future<void>.value();

      final a = DeflockOfflineTileImageProvider(
        coordinates: coords1,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'url1',
      );
      final b = DeflockOfflineTileImageProvider(
        coordinates: coords2,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'url2',
      );

      expect(a, isNot(equals(b)));
    });

    test('not equal for different provider or type', () {
      const coords = TileCoordinates(1, 2, 3);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancel = Future<void>.value();

      final base = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'url',
      );
      final diffProvider = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_b',
        tileTypeId: 'type_1',
        tileUrl: 'url',
      );
      final diffType = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_2',
        tileUrl: 'url',
      );

      expect(base, isNot(equals(diffProvider)));
      expect(base.hashCode, isNot(equals(diffProvider.hashCode)));
      expect(base, isNot(equals(diffType)));
      expect(base.hashCode, isNot(equals(diffType.hashCode)));
    });

    test('equality ignores cachingProvider and onNetworkSuccess', () {
      const coords = TileCoordinates(1, 2, 3);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancel = Future<void>.value();

      final withCaching = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'url',
        cachingProvider: MockMapCachingProvider(),
        onNetworkSuccess: () {},
      );
      final withoutCaching = DeflockOfflineTileImageProvider(
        coordinates: coords,
        options: options,
        httpClient: http.Client(),
        headers: const {},
        cancelLoading: cancel,
        isOfflineOnly: false,
        providerId: 'prov_a',
        tileTypeId: 'type_1',
        tileUrl: 'url',
      );

      expect(withCaching, equals(withoutCaching));
      expect(withCaching.hashCode, equals(withoutCaching.hashCode));
    });
  });

  group('DeflockTileProvider caching integration', () {
    test('passes cachingProvider through to offline path', () {
      when(() => mockAppState.offlineMode).thenReturn(true);

      final mockCaching = MockMapCachingProvider();
      var successCalled = false;

      final cachingProvider = DeflockTileProvider(
        providerId: 'openstreetmap',
        tileType: osmTileType,
        cachingProvider: mockCaching,
        onNetworkSuccess: () => successCalled = true,
      );

      const coords = TileCoordinates(5, 10, 12);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancelLoading = Future<void>.value();

      final imageProvider = cachingProvider.getImageWithCancelLoadingSupport(
        coords,
        options,
        cancelLoading,
      );

      expect(imageProvider, isA<DeflockOfflineTileImageProvider>());
      final offlineProvider = imageProvider as DeflockOfflineTileImageProvider;
      expect(offlineProvider.cachingProvider, same(mockCaching));
      expect(offlineProvider.onNetworkSuccess, isNotNull);

      // Invoke the callback to verify it's wired correctly
      offlineProvider.onNetworkSuccess!();
      expect(successCalled, isTrue);

      cachingProvider.shutdown();
    });

    test('offline provider has null caching when not provided', () {
      when(() => mockAppState.offlineMode).thenReturn(true);

      const coords = TileCoordinates(5, 10, 12);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final cancelLoading = Future<void>.value();

      final imageProvider = provider.getImageWithCancelLoadingSupport(
        coords,
        options,
        cancelLoading,
      );

      expect(imageProvider, isA<DeflockOfflineTileImageProvider>());
      final offlineProvider = imageProvider as DeflockOfflineTileImageProvider;
      expect(offlineProvider.cachingProvider, isNull);
      expect(offlineProvider.onNetworkSuccess, isNull);
    });
  });

  group('DeflockOfflineTileImageProvider caching helpers', () {
    late Directory tempDir;
    late ProviderTileCacheStore cacheStore;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tile_cache_test_');
      cacheStore = ProviderTileCacheStore(cacheDirectory: tempDir.path);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('disk cache integration: putTile then getTile round-trip', () async {
      const url = 'https://tile.example.com/3/1/2.png';
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final metadata = CachedMapTileMetadata(
        staleAt: DateTime.timestamp().add(const Duration(hours: 1)),
        lastModified: DateTime.utc(2026, 2, 20),
        etag: '"tile-etag"',
      );

      // Write to cache
      await cacheStore.putTile(url: url, metadata: metadata, bytes: bytes);

      // Read back
      final cached = await cacheStore.getTile(url);
      expect(cached, isNotNull);
      expect(cached!.bytes, equals(bytes));
      expect(cached.metadata.etag, equals('"tile-etag"'));
      expect(cached.metadata.isStale, isFalse);
    });

    test('disk cache: stale tiles are detectable', () async {
      const url = 'https://tile.example.com/stale.png';
      final bytes = Uint8List.fromList([1, 2, 3]);
      final metadata = CachedMapTileMetadata(
        staleAt: DateTime.timestamp().subtract(const Duration(hours: 1)),
        lastModified: null,
        etag: null,
      );

      await cacheStore.putTile(url: url, metadata: metadata, bytes: bytes);

      final cached = await cacheStore.getTile(url);
      expect(cached, isNotNull);
      expect(cached!.metadata.isStale, isTrue);
      // Bytes are still available even when stale (for conditional revalidation)
      expect(cached.bytes, equals(bytes));
    });

    test('disk cache: metadata-only update preserves bytes', () async {
      const url = 'https://tile.example.com/revalidated.png';
      final bytes = Uint8List.fromList([10, 20, 30]);

      // Initial write with bytes
      await cacheStore.putTile(
        url: url,
        metadata: CachedMapTileMetadata(
          staleAt: DateTime.timestamp().subtract(const Duration(hours: 1)),
          lastModified: null,
          etag: '"v1"',
        ),
        bytes: bytes,
      );

      // Metadata-only update (simulating 304 Not Modified revalidation)
      await cacheStore.putTile(
        url: url,
        metadata: CachedMapTileMetadata(
          staleAt: DateTime.timestamp().add(const Duration(hours: 1)),
          lastModified: null,
          etag: '"v2"',
        ),
        // No bytes — metadata only
      );

      final cached = await cacheStore.getTile(url);
      expect(cached, isNotNull);
      expect(cached!.bytes, equals(bytes)); // original bytes preserved
      expect(cached.metadata.etag, equals('"v2"')); // metadata updated
      expect(cached.metadata.isStale, isFalse); // now fresh
    });
  });

  group('DeflockOfflineTileImageProvider load error paths', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    /// Load the tile via [loadImage] and return the first error from the
    /// image stream.  The decode callback should never be reached on error
    /// paths, so we throw if it is.
    Future<Object> loadAndExpectError(
        DeflockOfflineTileImageProvider provider) {
      final completer = Completer<Object>();
      final stream = provider.loadImage(
        provider,
        (buffer, {getTargetSize}) async =>
            throw StateError('decode should not be called'),
      );
      stream.addListener(ImageStreamListener(
        (_, _) {
          if (!completer.isCompleted) {
            completer
                .completeError(StateError('expected error but got image'));
          }
        },
        onError: (error, _) {
          if (!completer.isCompleted) completer.complete(error);
        },
      ));
      return completer.future;
    }

    test('offline both-miss throws TileNotAvailableOfflineException',
        () async {
      // No offline areas, no cache → both miss.
      final error = await loadAndExpectError(
        DeflockOfflineTileImageProvider(
          coordinates: const TileCoordinates(1, 2, 3),
          options: TileLayer(urlTemplate: 'test/{z}/{x}/{y}'),
          httpClient: http.Client(),
          headers: const {},
          cancelLoading: Completer<void>().future, // never cancels
          isOfflineOnly: true,
          providerId: 'nonexistent',
          tileTypeId: 'nonexistent',
          tileUrl: 'https://example.com/3/1/2.png',
        ),
      );

      expect(error, isA<TileNotAvailableOfflineException>());
    });

    test('cancelled offline tile throws TileLoadCancelledException',
        () async {
      // cancelLoading already resolved → _loadAsync catch block detects
      // cancellation and throws TileLoadCancelledException instead of
      // the underlying TileNotAvailableOfflineException.
      final error = await loadAndExpectError(
        DeflockOfflineTileImageProvider(
          coordinates: const TileCoordinates(1, 2, 3),
          options: TileLayer(urlTemplate: 'test/{z}/{x}/{y}'),
          httpClient: http.Client(),
          headers: const {},
          cancelLoading: Future<void>.value(), // already cancelled
          isOfflineOnly: true,
          providerId: 'nonexistent',
          tileTypeId: 'nonexistent',
          tileUrl: 'https://example.com/3/1/2.png',
        ),
      );

      expect(error, isA<TileLoadCancelledException>());
    });

    test('online cancel before network throws TileLoadCancelledException',
        () async {
      // Online mode: cache miss, local miss, then cancelled check fires
      // before reaching the network fetch.
      final error = await loadAndExpectError(
        DeflockOfflineTileImageProvider(
          coordinates: const TileCoordinates(1, 2, 3),
          options: TileLayer(urlTemplate: 'test/{z}/{x}/{y}'),
          httpClient: http.Client(),
          headers: const {},
          cancelLoading: Future<void>.value(), // already cancelled
          isOfflineOnly: false,
          providerId: 'nonexistent',
          tileTypeId: 'nonexistent',
          tileUrl: 'https://example.com/3/1/2.png',
        ),
      );

      expect(error, isA<TileLoadCancelledException>());
    });

    test('network error throws HttpException', () async {
      // Online mode: cache miss, local miss, not cancelled, network
      // returns 500 → HttpException with tile coordinates and status.
      final error = await loadAndExpectError(
        DeflockOfflineTileImageProvider(
          coordinates: const TileCoordinates(4, 5, 6),
          options: TileLayer(urlTemplate: 'test/{z}/{x}/{y}'),
          httpClient: MockClient((_) async => http.Response('', 500)),
          headers: const {},
          cancelLoading: Completer<void>().future, // never cancels
          isOfflineOnly: false,
          providerId: 'nonexistent',
          tileTypeId: 'nonexistent',
          tileUrl: 'https://example.com/6/4/5.png',
        ),
      );

      expect(error, isA<HttpException>());
      expect((error as HttpException).message, contains('6/4/5'));
      expect(error.message, contains('500'));
    });
  });
}

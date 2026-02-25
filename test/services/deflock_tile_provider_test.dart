import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/models/tile_provider.dart' as models;
import 'package:deflockapp/services/deflock_tile_provider.dart';

class MockAppState extends Mock implements AppState {}

void main() {
  late DeflockTileProvider provider;
  late MockAppState mockAppState;

  const osmTileType = models.TileType(
    id: 'osm_street',
    name: 'Street Map',
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap',
    maxZoom: 19,
  );

  const mapboxTileType = models.TileType(
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
    await provider.dispose();
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
      await provider.dispose();
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
  });
}

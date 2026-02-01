import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/services/deflock_tile_provider.dart';
import 'package:deflockapp/services/map_data_provider.dart';

class MockAppState extends Mock implements AppState {}

void main() {
  group('DeflockTileProvider', () {
    late DeflockTileProvider provider;
    late MockAppState mockAppState;

    setUp(() {
      provider = DeflockTileProvider();
      mockAppState = MockAppState();
      when(() => mockAppState.selectedTileProvider).thenReturn(null);
      when(() => mockAppState.selectedTileType).thenReturn(null);
      AppState.instance = mockAppState;
    });

    test('creates image provider for tile coordinates', () {
      const coordinates = TileCoordinates(0, 0, 0);
      final options = TileLayer(
        urlTemplate: 'test/{z}/{x}/{y}',
      );

      final imageProvider = provider.getImage(coordinates, options);

      expect(imageProvider, isA<DeflockTileImageProvider>());
      expect((imageProvider as DeflockTileImageProvider).coordinates,
          equals(coordinates));
    });
  });

  group('DeflockTileImageProvider', () {
    test('generates consistent keys for same coordinates', () {
      const coordinates1 = TileCoordinates(1, 2, 3);
      const coordinates2 = TileCoordinates(1, 2, 3);
      const coordinates3 = TileCoordinates(1, 2, 4);

      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');

      final mapDataProvider = MapDataProvider();

      final provider1 = DeflockTileImageProvider(
        coordinates: coordinates1,
        options: options,
        mapDataProvider: mapDataProvider,
        providerId: 'test_provider',
        tileTypeId: 'test_type',
      );
      final provider2 = DeflockTileImageProvider(
        coordinates: coordinates2,
        options: options,
        mapDataProvider: mapDataProvider,
        providerId: 'test_provider',
        tileTypeId: 'test_type',
      );
      final provider3 = DeflockTileImageProvider(
        coordinates: coordinates3,
        options: options,
        mapDataProvider: mapDataProvider,
        providerId: 'test_provider',
        tileTypeId: 'test_type',
      );

      // Same coordinates should be equal
      expect(provider1, equals(provider2));
      expect(provider1.hashCode, equals(provider2.hashCode));

      // Different coordinates should not be equal
      expect(provider1, isNot(equals(provider3)));
    });

    test('generates different keys for different providers/types', () {
      const coordinates = TileCoordinates(1, 2, 3);
      final options = TileLayer(urlTemplate: 'test/{z}/{x}/{y}');
      final mapDataProvider = MapDataProvider();

      final provider1 = DeflockTileImageProvider(
        coordinates: coordinates,
        options: options,
        mapDataProvider: mapDataProvider,
        providerId: 'provider_a',
        tileTypeId: 'type_1',
      );
      final provider2 = DeflockTileImageProvider(
        coordinates: coordinates,
        options: options,
        mapDataProvider: mapDataProvider,
        providerId: 'provider_b',
        tileTypeId: 'type_1',
      );
      final provider3 = DeflockTileImageProvider(
        coordinates: coordinates,
        options: options,
        mapDataProvider: mapDataProvider,
        providerId: 'provider_a',
        tileTypeId: 'type_2',
      );

      // Different providers should not be equal (even with same coordinates)
      expect(provider1, isNot(equals(provider2)));
      expect(provider1.hashCode, isNot(equals(provider2.hashCode)));

      // Different tile types should not be equal (even with same coordinates and provider)
      expect(provider1, isNot(equals(provider3)));
      expect(provider1.hashCode, isNot(equals(provider3.hashCode)));
    });
  });
}

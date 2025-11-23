import 'package:flutter_test/flutter_test.dart';
import 'package:flock_map_app/models/tile_provider.dart';

void main() {
  group('TileType', () {
    test('getTileUrl handles standard x/y/z replacement', () {
      final tileType = TileType(
        id: 'test',
        name: 'Test',
        urlTemplate: 'https://example.com/{z}/{x}/{y}.png',
        attribution: 'Test',
      );

      final url = tileType.getTileUrl(3, 2, 1);
      expect(url, 'https://example.com/3/2/1.png');
    });

    test('getTileUrl handles subdomain patterns', () {
      final tileType0_3 = TileType(
        id: 'test_0_3',
        name: 'Test 0-3',
        urlTemplate: 'https://s{0_3}.example.com/{z}/{x}/{y}.png',
        attribution: 'Test',
      );

      final tileType1_4 = TileType(
        id: 'test_1_4',
        name: 'Test 1-4',
        urlTemplate: 'https://s{1_4}.example.com/{z}/{x}/{y}.png',
        attribution: 'Test',
      );

      // Test 0-3 range
      final url_0_3_a = tileType0_3.getTileUrl(1, 0, 0);
      final url_0_3_b = tileType0_3.getTileUrl(1, 3, 0);
      expect(url_0_3_a, contains('s0.example.com'));
      expect(url_0_3_b, contains('s3.example.com'));

      // Test 1-4 range
      final url_1_4_a = tileType1_4.getTileUrl(1, 0, 0);
      final url_1_4_b = tileType1_4.getTileUrl(1, 3, 0);
      expect(url_1_4_a, contains('s1.example.com'));
      expect(url_1_4_b, contains('s4.example.com'));

      // Test consistency
      final url1 = tileType0_3.getTileUrl(1, 2, 3);
      final url2 = tileType0_3.getTileUrl(1, 2, 3);
      expect(url1, url2); // Same input should give same output
    });

    test('getTileUrl handles Bing Maps quadkey conversion', () {
      final tileType = TileType(
        id: 'bing_test',
        name: 'Bing Test',
        urlTemplate: 'https://ecn.t{subdomain}.tiles.virtualearth.net/tiles/a{quadkey}.jpeg?g=1&n=z',
        attribution: 'Microsoft',
      );

      // Test some known quadkey conversions
      // x=0, y=0, z=1 should give quadkey "0"
      final url1 = tileType.getTileUrl(1, 0, 0);
      expect(url1, contains('a0.jpeg'));

      // x=1, y=0, z=1 should give quadkey "1" 
      final url2 = tileType.getTileUrl(1, 1, 0);
      expect(url2, contains('a1.jpeg'));

      // x=0, y=1, z=1 should give quadkey "2"
      final url3 = tileType.getTileUrl(1, 0, 1);
      expect(url3, contains('a2.jpeg'));

      // x=1, y=1, z=1 should give quadkey "3"
      final url4 = tileType.getTileUrl(1, 1, 1);
      expect(url4, contains('a3.jpeg'));

      // More complex example: x=3, y=5, z=3 should give quadkey "213"
      final url5 = tileType.getTileUrl(3, 3, 5);
      expect(url5, contains('a213.jpeg'));
    });

    test('getTileUrl handles API key replacement', () {
      final tileType = TileType(
        id: 'test',
        name: 'Test',
        urlTemplate: 'https://api.example.com/{z}/{x}/{y}?key={api_key}',
        attribution: 'Test',
      );

      final url = tileType.getTileUrl(1, 2, 3, apiKey: 'mykey123');
      expect(url, 'https://api.example.com/1/2/3?key=mykey123');
    });

    test('requiresApiKey detects API key requirement correctly', () {
      final tileTypeWithKey = TileType(
        id: 'test1',
        name: 'Test 1',
        urlTemplate: 'https://api.example.com/{z}/{x}/{y}?key={api_key}',
        attribution: 'Test',
      );

      final tileTypeWithoutKey = TileType(
        id: 'test2',
        name: 'Test 2',
        urlTemplate: 'https://example.com/{z}/{x}/{y}.png',
        attribution: 'Test',
      );

      expect(tileTypeWithKey.requiresApiKey, isTrue);
      expect(tileTypeWithoutKey.requiresApiKey, isFalse);
    });
  });

  group('DefaultTileProviders', () {
    test('contains Bing satellite provider', () {
      final providers = DefaultTileProviders.createDefaults();
      final bingProvider = providers.firstWhere((p) => p.id == 'bing');
      
      expect(bingProvider.name, 'Bing Maps');
      expect(bingProvider.tileTypes, hasLength(1));
      
      final satelliteType = bingProvider.tileTypes.first;
      expect(satelliteType.id, 'bing_satellite');
      expect(satelliteType.name, 'Satellite');
      expect(satelliteType.urlTemplate, contains('quadkey'));
      expect(satelliteType.urlTemplate, contains('0_3'));
      expect(satelliteType.requiresApiKey, isFalse);
      expect(satelliteType.attribution, '© Microsoft Corporation');
    });

    test('all default providers are usable', () {
      final providers = DefaultTileProviders.createDefaults();
      for (final provider in providers) {
        expect(provider.isUsable, isTrue, reason: '${provider.name} should be usable');
      }
    });
  });
}
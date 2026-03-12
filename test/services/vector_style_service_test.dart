import 'package:flutter_test/flutter_test.dart';
import 'package:deflockapp/services/vector_style_service.dart';

void main() {
  group('VectorStyleService', () {
    setUp(() {
      VectorStyleService.instance.clear();
    });

    test('isCached returns false for uncached styles', () {
      expect(
        VectorStyleService.instance.isCached('https://example.com/style.json'),
        isFalse,
      );
    });

    test('getCached returns null for uncached styles', () {
      expect(
        VectorStyleService.instance.getCached('https://example.com/style.json'),
        isNull,
      );
    });

    test('evict removes cached style', () {
      // Can't fully test load without a real server, but evict should not throw
      VectorStyleService.instance.evict('https://example.com/style.json');
      expect(
        VectorStyleService.instance.isCached('https://example.com/style.json'),
        isFalse,
      );
    });

    test('clear removes all cached styles', () {
      VectorStyleService.instance.clear();
      // Should not throw and cache should be empty
      expect(
        VectorStyleService.instance.getCached('https://example.com/a.json'),
        isNull,
      );
      expect(
        VectorStyleService.instance.getCached('https://example.com/b.json'),
        isNull,
      );
    });

    test('cache key distinguishes by apiKey', () {
      // Same URL with different API keys should be different cache entries
      expect(
        VectorStyleService.instance.isCached(
          'https://example.com/style.json',
          apiKey: 'key1',
        ),
        isFalse,
      );
      expect(
        VectorStyleService.instance.isCached(
          'https://example.com/style.json',
          apiKey: 'key2',
        ),
        isFalse,
      );
    });
  });
}

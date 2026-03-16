import 'package:flutter_test/flutter_test.dart';
import 'package:deflockapp/models/service_endpoint.dart';

void main() {
  group('ServiceEndpoint', () {
    test('toJson/fromJson round-trip preserves all fields', () {
      const endpoint = ServiceEndpoint(
        id: 'test', name: 'Test', url: 'https://example.com',
        enabled: false, isBuiltIn: true, maxRetries: 5, timeoutSeconds: 10,
      );
      final restored = ServiceEndpoint.fromJson(endpoint.toJson());
      expect(restored.id, endpoint.id);
      expect(restored.name, endpoint.name);
      expect(restored.url, endpoint.url);
      expect(restored.enabled, endpoint.enabled);
      expect(restored.isBuiltIn, endpoint.isBuiltIn);
      expect(restored.maxRetries, endpoint.maxRetries);
      expect(restored.timeoutSeconds, endpoint.timeoutSeconds);
    });

    test('fromJson uses defaults for missing optional fields', () {
      final endpoint = ServiceEndpoint.fromJson({
        'id': 'x', 'name': 'X', 'url': 'https://x.com',
      });
      expect(endpoint.enabled, isTrue);
      expect(endpoint.isBuiltIn, isFalse);
      expect(endpoint.maxRetries, isNull);
      expect(endpoint.timeoutSeconds, isNull);
    });

    test('copyWith replaces specified fields only', () {
      const original = ServiceEndpoint(
        id: 'a', name: 'A', url: 'https://a.com',
      );
      final modified = original.copyWith(name: 'B', enabled: false);
      expect(modified.id, 'a');
      expect(modified.name, 'B');
      expect(modified.url, 'https://a.com');
      expect(modified.enabled, isFalse);
    });

    test('equality is by id', () {
      const a = ServiceEndpoint(id: 'x', name: 'A', url: 'https://a.com');
      const b = ServiceEndpoint(id: 'x', name: 'B', url: 'https://b.com');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different ids are not equal', () {
      const a = ServiceEndpoint(id: 'x', name: 'A', url: 'https://a.com');
      const b = ServiceEndpoint(id: 'y', name: 'A', url: 'https://a.com');
      expect(a, isNot(equals(b)));
    });
  });

  group('DefaultServiceEndpoints', () {
    test('routing returns 2 built-in endpoints', () {
      final endpoints = DefaultServiceEndpoints.routing();
      expect(endpoints, hasLength(2));
      expect(endpoints.every((e) => e.isBuiltIn), isTrue);
      expect(endpoints.every((e) => e.enabled), isTrue);
    });

    test('overpass returns 2 built-in endpoints', () {
      final endpoints = DefaultServiceEndpoints.overpass();
      expect(endpoints, hasLength(2));
      expect(endpoints.every((e) => e.isBuiltIn), isTrue);
      expect(endpoints.every((e) => e.enabled), isTrue);
    });

    test('routing endpoints have expected URLs', () {
      final endpoints = DefaultServiceEndpoints.routing();
      expect(endpoints[0].url, contains('dontgetflocked.com'));
      expect(endpoints[1].url, contains('alprwatch.org'));
    });

    test('overpass endpoints have expected URLs', () {
      final endpoints = DefaultServiceEndpoints.overpass();
      expect(endpoints[0].url, contains('overpass.deflock.org'));
      expect(endpoints[1].url, contains('overpass-api.de'));
    });
  });
}

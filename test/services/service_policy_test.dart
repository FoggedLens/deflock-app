import 'package:flutter_test/flutter_test.dart';

import 'package:deflock/services/service_policy.dart';

void main() {
  group('ServicePolicyResolver', () {
    setUp(() {
      ServicePolicyResolver.clearCustomPolicies();
    });

    group('resolveType', () {
      test('resolves OSM editing API from production URL', () {
        expect(
          ServicePolicyResolver.resolveType('https://api.openstreetmap.org/api/0.6/map?bbox=1,2,3,4'),
          ServiceType.osmEditingApi,
        );
      });

      test('resolves OSM editing API from sandbox URL', () {
        expect(
          ServicePolicyResolver.resolveType('https://api06.dev.openstreetmap.org/api/0.6/map?bbox=1,2,3,4'),
          ServiceType.osmEditingApi,
        );
      });

      test('resolves OSM editing API from dev URL', () {
        expect(
          ServicePolicyResolver.resolveType('https://master.apis.dev.openstreetmap.org/api/0.6/user/details'),
          ServiceType.osmEditingApi,
        );
      });

      test('resolves OSM tile server from tile URL', () {
        expect(
          ServicePolicyResolver.resolveType('https://tile.openstreetmap.org/12/1234/5678.png'),
          ServiceType.osmTileServer,
        );
      });

      test('resolves Nominatim from geocoding URL', () {
        expect(
          ServicePolicyResolver.resolveType('https://nominatim.openstreetmap.org/search?q=London'),
          ServiceType.nominatim,
        );
      });

      test('resolves Overpass API', () {
        expect(
          ServicePolicyResolver.resolveType('https://overpass-api.de/api/interpreter'),
          ServiceType.overpass,
        );
      });

      test('resolves TagInfo', () {
        expect(
          ServicePolicyResolver.resolveType('https://taginfo.openstreetmap.org/api/4/key/values'),
          ServiceType.tagInfo,
        );
      });

      test('resolves Bing tiles from virtualearth URL', () {
        expect(
          ServicePolicyResolver.resolveType('https://ecn.t0.tiles.virtualearth.net/tiles/a12345.jpeg'),
          ServiceType.bingTiles,
        );
      });

      test('resolves Mapbox tiles', () {
        expect(
          ServicePolicyResolver.resolveType('https://api.mapbox.com/v4/mapbox.satellite/12/1234/5678@2x.jpg90'),
          ServiceType.mapboxTiles,
        );
      });

      test('returns custom for unknown host', () {
        expect(
          ServicePolicyResolver.resolveType('https://tiles.myserver.com/12/1234/5678.png'),
          ServiceType.custom,
        );
      });

      test('returns custom for empty string', () {
        expect(
          ServicePolicyResolver.resolveType(''),
          ServiceType.custom,
        );
      });

      test('returns custom for malformed URL', () {
        expect(
          ServicePolicyResolver.resolveType('not-a-url'),
          ServiceType.custom,
        );
      });
    });

    group('resolve', () {
      test('OSM tile server policy disallows offline download', () {
        final policy = ServicePolicyResolver.resolve(
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        );
        expect(policy.allowsOfflineDownload, false);
      });

      test('OSM tile server policy requires 7-day min cache TTL', () {
        final policy = ServicePolicyResolver.resolve(
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        );
        expect(policy.minCacheTtl, const Duration(days: 7));
      });

      test('OSM tile server has attribution URL', () {
        final policy = ServicePolicyResolver.resolve(
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        );
        expect(policy.attributionUrl, 'https://www.openstreetmap.org/copyright');
      });

      test('Nominatim policy enforces 1-second rate limit', () {
        final policy = ServicePolicyResolver.resolve(
          'https://nominatim.openstreetmap.org/search?q=test',
        );
        expect(policy.minRequestInterval, const Duration(seconds: 1));
      });

      test('Nominatim policy requires client caching', () {
        final policy = ServicePolicyResolver.resolve(
          'https://nominatim.openstreetmap.org/search?q=test',
        );
        expect(policy.requiresClientCaching, true);
      });

      test('Nominatim has attribution URL', () {
        final policy = ServicePolicyResolver.resolve(
          'https://nominatim.openstreetmap.org/search?q=test',
        );
        expect(policy.attributionUrl, 'https://www.openstreetmap.org/copyright');
      });

      test('OSM editing API allows max 2 concurrent requests', () {
        final policy = ServicePolicyResolver.resolve(
          'https://api.openstreetmap.org/api/0.6/map?bbox=1,2,3,4',
        );
        expect(policy.maxConcurrentRequests, 2);
      });

      test('Bing tiles allow offline download', () {
        final policy = ServicePolicyResolver.resolve(
          'https://ecn.t0.tiles.virtualearth.net/tiles/a{quadkey}.jpeg?g=1&n=z',
        );
        expect(policy.allowsOfflineDownload, true);
      });

      test('Mapbox tiles allow offline download', () {
        final policy = ServicePolicyResolver.resolve(
          'https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90',
        );
        expect(policy.allowsOfflineDownload, true);
      });

      test('custom/unknown host gets permissive defaults', () {
        final policy = ServicePolicyResolver.resolve(
          'https://tiles.myserver.com/{z}/{x}/{y}.png',
        );
        expect(policy.allowsOfflineDownload, true);
        expect(policy.minRequestInterval, isNull);
        expect(policy.requiresClientCaching, false);
        expect(policy.attributionUrl, isNull);
      });
    });

    group('resolve with URL templates', () {
      test('handles {z}/{x}/{y} template variables', () {
        final policy = ServicePolicyResolver.resolve(
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        );
        expect(policy.allowsOfflineDownload, false);
      });

      test('handles {quadkey} template variable', () {
        final policy = ServicePolicyResolver.resolve(
          'https://ecn.t{0_3}.tiles.virtualearth.net/tiles/a{quadkey}.jpeg?g=1',
        );
        expect(policy.allowsOfflineDownload, true);
      });

      test('handles {0_3} subdomain template', () {
        final type = ServicePolicyResolver.resolveType(
          'https://ecn.t{0_3}.tiles.virtualearth.net/tiles/a{quadkey}.jpeg',
        );
        expect(type, ServiceType.bingTiles);
      });

      test('handles {api_key} template variable', () {
        final type = ServicePolicyResolver.resolveType(
          'https://api.mapbox.com/v4/mapbox.satellite/{z}/{x}/{y}@2x.jpg90?access_token={api_key}',
        );
        expect(type, ServiceType.mapboxTiles);
      });
    });

    group('custom policy overrides', () {
      test('custom override takes precedence over built-in', () {
        ServicePolicyResolver.registerCustomPolicy(
          'overpass-api.de',
          const ServicePolicy.custom(maxConcurrent: 20, allowsOffline: true),
        );

        final policy = ServicePolicyResolver.resolve(
          'https://overpass-api.de/api/interpreter',
        );
        expect(policy.maxConcurrentRequests, 20);
      });

      test('custom policy for self-hosted tiles allows offline', () {
        ServicePolicyResolver.registerCustomPolicy(
          'tiles.myserver.com',
          const ServicePolicy.custom(allowsOffline: true, maxConcurrent: 16),
        );

        final policy = ServicePolicyResolver.resolve(
          'https://tiles.myserver.com/{z}/{x}/{y}.png',
        );
        expect(policy.allowsOfflineDownload, true);
        expect(policy.maxConcurrentRequests, 16);
      });

      test('removing custom override restores built-in policy', () {
        ServicePolicyResolver.registerCustomPolicy(
          'overpass-api.de',
          const ServicePolicy.custom(maxConcurrent: 20),
        );
        expect(
          ServicePolicyResolver.resolve('https://overpass-api.de/api/interpreter').maxConcurrentRequests,
          20,
        );

        ServicePolicyResolver.removeCustomPolicy('overpass-api.de');
        // Should fall back to built-in Overpass policy (maxConcurrent: 0 = managed elsewhere)
        expect(
          ServicePolicyResolver.resolve('https://overpass-api.de/api/interpreter').maxConcurrentRequests,
          0,
        );
      });

      test('clearCustomPolicies removes all overrides', () {
        ServicePolicyResolver.registerCustomPolicy('a.com', const ServicePolicy.custom(maxConcurrent: 1));
        ServicePolicyResolver.registerCustomPolicy('b.com', const ServicePolicy.custom(maxConcurrent: 2));

        ServicePolicyResolver.clearCustomPolicies();

        // Both should now return custom (default) policy
        expect(
          ServicePolicyResolver.resolve('https://a.com/test').maxConcurrentRequests,
          8, // default custom maxConcurrent
        );
      });
    });
  });

  group('ServiceRateLimiter', () {
    setUp(() {
      ServiceRateLimiter.reset();
    });

    test('acquire and release work for editing API (2 concurrent)', () async {
      // Should be able to acquire 2 slots without blocking
      await ServiceRateLimiter.acquire(ServiceType.osmEditingApi);
      await ServiceRateLimiter.acquire(ServiceType.osmEditingApi);

      // Release both
      ServiceRateLimiter.release(ServiceType.osmEditingApi);
      ServiceRateLimiter.release(ServiceType.osmEditingApi);
    });

    test('Nominatim rate limiting delays rapid requests', () async {
      final start = DateTime.now();

      // First request should be immediate
      await ServiceRateLimiter.acquire(ServiceType.nominatim);
      ServiceRateLimiter.release(ServiceType.nominatim);

      // Second request should be delayed by ~1 second
      await ServiceRateLimiter.acquire(ServiceType.nominatim);
      ServiceRateLimiter.release(ServiceType.nominatim);

      final elapsed = DateTime.now().difference(start);
      // Should have taken at least 900ms (allowing some tolerance)
      expect(elapsed.inMilliseconds, greaterThanOrEqualTo(900));
    });

    test('services with no rate limit pass through immediately', () async {
      // Overpass has maxConcurrentRequests: 0, so acquire should be immediate
      final start = DateTime.now();
      await ServiceRateLimiter.acquire(ServiceType.overpass);
      ServiceRateLimiter.release(ServiceType.overpass);
      await ServiceRateLimiter.acquire(ServiceType.overpass);
      ServiceRateLimiter.release(ServiceType.overpass);
      final elapsed = DateTime.now().difference(start);
      expect(elapsed.inMilliseconds, lessThan(100));
    });
  });

  group('ServicePolicy', () {
    test('osmTileServer policy has correct values', () {
      const policy = ServicePolicy.osmTileServer();
      expect(policy.allowsOfflineDownload, false);
      expect(policy.minCacheTtl, const Duration(days: 7));
      expect(policy.requiresClientCaching, true);
      expect(policy.attributionUrl, 'https://www.openstreetmap.org/copyright');
      expect(policy.maxConcurrentRequests, 0); // managed by flutter_map
    });

    test('nominatim policy has correct values', () {
      const policy = ServicePolicy.nominatim();
      expect(policy.minRequestInterval, const Duration(seconds: 1));
      expect(policy.maxConcurrentRequests, 1);
      expect(policy.requiresClientCaching, true);
      expect(policy.attributionUrl, 'https://www.openstreetmap.org/copyright');
    });

    test('osmEditingApi policy has correct values', () {
      const policy = ServicePolicy.osmEditingApi();
      expect(policy.maxConcurrentRequests, 2);
      expect(policy.minRequestInterval, isNull);
    });

    test('custom policy uses permissive defaults', () {
      const policy = ServicePolicy();
      expect(policy.maxConcurrentRequests, 8);
      expect(policy.allowsOfflineDownload, true);
      expect(policy.minRequestInterval, isNull);
      expect(policy.requiresClientCaching, false);
      expect(policy.minCacheTtl, isNull);
      expect(policy.attributionUrl, isNull);
    });

    test('custom policy accepts overrides', () {
      const policy = ServicePolicy.custom(
        maxConcurrent: 20,
        allowsOffline: false,
        attribution: 'https://example.com/license',
      );
      expect(policy.maxConcurrentRequests, 20);
      expect(policy.allowsOfflineDownload, false);
      expect(policy.attributionUrl, 'https://example.com/license');
    });
  });
}

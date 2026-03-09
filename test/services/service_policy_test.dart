import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deflockapp/services/service_policy.dart';

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
      test('OSM tile server policy allows offline download', () {
        final policy = ServicePolicyResolver.resolve(
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        );
        expect(policy.allowsOfflineDownload, true);
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
        expect(policy.allowsOfflineDownload, true);
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

    test('third acquire blocks until a slot is released', () async {
      // Fill both slots (osmEditingApi maxConcurrentRequests = 2)
      await ServiceRateLimiter.acquire(ServiceType.osmEditingApi);
      await ServiceRateLimiter.acquire(ServiceType.osmEditingApi);

      // Third acquire should block
      var thirdCompleted = false;
      final thirdFuture = ServiceRateLimiter.acquire(ServiceType.osmEditingApi).then((_) {
        thirdCompleted = true;
      });

      // Give microtasks a chance to run — third should still be blocked
      await Future<void>.delayed(Duration.zero);
      expect(thirdCompleted, false);

      // Release one slot — third should now complete
      ServiceRateLimiter.release(ServiceType.osmEditingApi);
      await thirdFuture;
      expect(thirdCompleted, true);

      // Clean up
      ServiceRateLimiter.release(ServiceType.osmEditingApi);
      ServiceRateLimiter.release(ServiceType.osmEditingApi);
    });

    test('Nominatim rate limiting delays rapid requests', () {
      fakeAsync((async) {
        ServiceRateLimiter.clock = () => async.getClock(DateTime(2026)).now();

        var acquireCount = 0;

        // First request should be immediate
        ServiceRateLimiter.acquire(ServiceType.nominatim).then((_) {
          acquireCount++;
          ServiceRateLimiter.release(ServiceType.nominatim);
        });
        async.flushMicrotasks();
        expect(acquireCount, 1);

        // Second request should be delayed by ~1 second
        ServiceRateLimiter.acquire(ServiceType.nominatim).then((_) {
          acquireCount++;
          ServiceRateLimiter.release(ServiceType.nominatim);
        });
        async.flushMicrotasks();
        expect(acquireCount, 1, reason: 'second acquire should be blocked');

        // Advance past the 1-second rate limit
        async.elapse(const Duration(seconds: 1));
        expect(acquireCount, 2, reason: 'second acquire should have completed');
      });
    });

    test('services with no rate limit pass through immediately', () {
      fakeAsync((async) {
        ServiceRateLimiter.clock = () => async.getClock(DateTime(2026)).now();

        var acquireCount = 0;

        // Overpass has maxConcurrentRequests: 0, so acquire should not apply
        // any artificial rate limiting delays.
        ServiceRateLimiter.acquire(ServiceType.overpass).then((_) {
          acquireCount++;
          ServiceRateLimiter.release(ServiceType.overpass);
        });
        async.flushMicrotasks();
        expect(acquireCount, 1);

        ServiceRateLimiter.acquire(ServiceType.overpass).then((_) {
          acquireCount++;
          ServiceRateLimiter.release(ServiceType.overpass);
        });
        async.flushMicrotasks();
        expect(acquireCount, 2);
      });
    });

    test('Nominatim enforces min interval under concurrent callers', () {
      fakeAsync((async) {
        ServiceRateLimiter.clock = () => async.getClock(DateTime(2026)).now();

        var completedCount = 0;

        // Start two concurrent callers; only one should run at a time and
        // the minRequestInterval of ~1s should still be enforced.
        ServiceRateLimiter.acquire(ServiceType.nominatim).then((_) {
          completedCount++;
          ServiceRateLimiter.release(ServiceType.nominatim);
        });
        ServiceRateLimiter.acquire(ServiceType.nominatim).then((_) {
          completedCount++;
          ServiceRateLimiter.release(ServiceType.nominatim);
        });

        async.flushMicrotasks();
        expect(completedCount, 1, reason: 'only first caller should complete immediately');

        // Advance past the 1-second rate limit
        async.elapse(const Duration(seconds: 1));
        expect(completedCount, 2, reason: 'second caller should complete after interval');
      });
    });
  });

  group('ServicePolicy', () {
    test('osmTileServer policy has correct values', () {
      const policy = ServicePolicy.osmTileServer();
      expect(policy.allowsOfflineDownload, true);
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

  group('ResiliencePolicy', () {
    test('retryDelay uses exponential backoff', () {
      const policy = ResiliencePolicy(
        retryBackoffBase: Duration(milliseconds: 100),
        retryBackoffMaxMs: 2000,
      );
      expect(policy.retryDelay(0), const Duration(milliseconds: 100));
      expect(policy.retryDelay(1), const Duration(milliseconds: 200));
      expect(policy.retryDelay(2), const Duration(milliseconds: 400));
    });

    test('retryDelay clamps to max', () {
      const policy = ResiliencePolicy(
        retryBackoffBase: Duration(milliseconds: 1000),
        retryBackoffMaxMs: 3000,
      );
      expect(policy.retryDelay(0), const Duration(milliseconds: 1000));
      expect(policy.retryDelay(1), const Duration(milliseconds: 2000));
      expect(policy.retryDelay(2), const Duration(milliseconds: 3000)); // clamped
      expect(policy.retryDelay(10), const Duration(milliseconds: 3000)); // clamped
    });
  });

  group('executeWithFallback', () {
    const policy = ResiliencePolicy(
      maxRetries: 2,
      retryBackoffBase: Duration.zero, // no delay in tests
    );

    test('abort error stops immediately, no fallback', () async {
      int callCount = 0;

      await expectLater(
        () => executeWithFallback<String>(
          primaryUrl: 'https://primary.example.com',
          fallbackUrl: 'https://fallback.example.com',
          execute: (url) {
            callCount++;
            throw Exception('bad request');
          },
          classifyError: (_) => ErrorDisposition.abort,
          policy: policy,
        ),
        throwsA(isA<Exception>()),
      );

      expect(callCount, 1); // no retries, no fallback
    });

    test('fallback error skips retries, goes to fallback', () async {
      final urlsSeen = <String>[];

      final result = await executeWithFallback<String>(
        primaryUrl: 'https://primary.example.com',
        fallbackUrl: 'https://fallback.example.com',
        execute: (url) {
          urlsSeen.add(url);
          if (url.contains('primary')) {
            throw Exception('rate limited');
          }
          return Future.value('ok from fallback');
        },
        classifyError: (_) => ErrorDisposition.fallback,
        policy: policy,
      );

      expect(result, 'ok from fallback');
      // 1 primary (no retries) + 1 fallback = 2
      expect(urlsSeen, ['https://primary.example.com', 'https://fallback.example.com']);
    });

    test('retry error retries N times then falls back', () async {
      final urlsSeen = <String>[];

      final result = await executeWithFallback<String>(
        primaryUrl: 'https://primary.example.com',
        fallbackUrl: 'https://fallback.example.com',
        execute: (url) {
          urlsSeen.add(url);
          if (url.contains('primary')) {
            throw Exception('server error');
          }
          return Future.value('ok from fallback');
        },
        classifyError: (_) => ErrorDisposition.retry,
        policy: policy,
      );

      expect(result, 'ok from fallback');
      // 3 primary attempts (1 + 2 retries) + 1 fallback = 4
      expect(urlsSeen.where((u) => u.contains('primary')).length, 3);
      expect(urlsSeen.where((u) => u.contains('fallback')).length, 1);
    });

    test('no fallback URL rethrows after retries', () async {
      int callCount = 0;

      await expectLater(
        () => executeWithFallback<String>(
          primaryUrl: 'https://primary.example.com',
          fallbackUrl: null,
          execute: (url) {
            callCount++;
            throw Exception('server error');
          },
          classifyError: (_) => ErrorDisposition.retry,
          policy: policy,
        ),
        throwsA(isA<Exception>()),
      );

      // 3 attempts (1 + 2 retries), then rethrow
      expect(callCount, 3);
    });

    test('fallback disposition with no fallback URL rethrows immediately', () async {
      int callCount = 0;

      await expectLater(
        () => executeWithFallback<String>(
          primaryUrl: 'https://primary.example.com',
          fallbackUrl: null,
          execute: (url) {
            callCount++;
            throw Exception('rate limited');
          },
          classifyError: (_) => ErrorDisposition.fallback,
          policy: policy,
        ),
        throwsA(isA<Exception>()),
      );

      // Only 1 attempt — fallback disposition skips retries, and no fallback URL
      expect(callCount, 1);
    });

    test('both fail propagates last error', () async {
      await expectLater(
        () => executeWithFallback<String>(
          primaryUrl: 'https://primary.example.com',
          fallbackUrl: 'https://fallback.example.com',
          execute: (url) {
            if (url.contains('fallback')) {
              throw Exception('fallback also failed');
            }
            throw Exception('primary failed');
          },
          classifyError: (_) => ErrorDisposition.retry,
          policy: policy,
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('fallback also failed'))),
      );
    });

    test('success on first try returns immediately', () async {
      int callCount = 0;

      final result = await executeWithFallback<String>(
        primaryUrl: 'https://primary.example.com',
        fallbackUrl: 'https://fallback.example.com',
        execute: (url) {
          callCount++;
          return Future.value('success');
        },
        classifyError: (_) => ErrorDisposition.retry,
        policy: policy,
      );

      expect(result, 'success');
      expect(callCount, 1);
    });

    test('success after retry does not try fallback', () async {
      int callCount = 0;

      final result = await executeWithFallback<String>(
        primaryUrl: 'https://primary.example.com',
        fallbackUrl: 'https://fallback.example.com',
        execute: (url) {
          callCount++;
          if (callCount == 1) throw Exception('transient');
          return Future.value('recovered');
        },
        classifyError: (_) => ErrorDisposition.retry,
        policy: policy,
      );

      expect(result, 'recovered');
      expect(callCount, 2); // 1 fail + 1 success, no fallback
    });
  });
}

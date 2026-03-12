import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deflockapp/models/service_endpoint.dart';
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

  group('executeWithEndpointList', () {
    const defaultPolicy = ResiliencePolicy(
      maxRetries: 1,
      retryBackoffBase: Duration.zero,
    );

    setUp(() {
      ResilienceMetrics().reset();
    });

    test('throws StateError when no endpoints enabled', () async {
      await expectLater(
        () => executeWithEndpointList<String>(
          endpoints: const [
            ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com', enabled: false),
          ],
          execute: (url) => Future.value('ok'),
          classifyError: (_) => ErrorDisposition.retry,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('succeeds with single enabled endpoint', () async {
      final result = await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
        ],
        execute: (url) => Future.value('ok'),
        classifyError: (_) => ErrorDisposition.retry,
      );
      expect(result, 'ok');
    });

    test('tries next endpoint when retry exhausted', () async {
      final urlsSeen = <String>[];

      final result = await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
          ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
        ],
        execute: (url) {
          urlsSeen.add(url);
          if (url == 'https://a.com') throw Exception('fail');
          return Future.value('ok from b');
        },
        classifyError: (_) => ErrorDisposition.retry,
        defaultPolicy: defaultPolicy,
      );

      expect(result, 'ok from b');
      // endpoint A: 1 attempt + 1 retry = 2 calls, then endpoint B: 1 call
      expect(urlsSeen.where((u) => u == 'https://a.com').length, 2);
      expect(urlsSeen.where((u) => u == 'https://b.com').length, 1);
    });

    test('fallback disposition skips to next immediately', () async {
      final urlsSeen = <String>[];

      final result = await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
          ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
        ],
        execute: (url) {
          urlsSeen.add(url);
          if (url == 'https://a.com') throw Exception('rate limited');
          return Future.value('ok from b');
        },
        classifyError: (_) => ErrorDisposition.fallback,
        defaultPolicy: defaultPolicy,
      );

      expect(result, 'ok from b');
      // Fallback: only 1 call to A (no retries), then 1 call to B
      expect(urlsSeen.where((u) => u == 'https://a.com').length, 1);
      expect(urlsSeen.where((u) => u == 'https://b.com').length, 1);
    });

    test('abort stops entire chain', () async {
      final urlsSeen = <String>[];

      await expectLater(
        () => executeWithEndpointList<String>(
          endpoints: const [
            ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
            ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
          ],
          execute: (url) {
            urlsSeen.add(url);
            throw Exception('validation error');
          },
          classifyError: (_) => ErrorDisposition.abort,
          defaultPolicy: defaultPolicy,
        ),
        throwsA(isA<Exception>()),
      );

      // Only A called once, B never called
      expect(urlsSeen, ['https://a.com']);
    });

    test('per-endpoint maxRetries override', () async {
      int callCount = 0;

      await expectLater(
        () => executeWithEndpointList<String>(
          endpoints: const [
            ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com', maxRetries: 0),
          ],
          execute: (url) {
            callCount++;
            throw Exception('fail');
          },
          classifyError: (_) => ErrorDisposition.retry,
          defaultPolicy: const ResiliencePolicy(
            maxRetries: 5,
            retryBackoffBase: Duration.zero,
          ),
        ),
        throwsA(isA<Exception>()),
      );

      // maxRetries=0 means only 1 attempt (no retries)
      expect(callCount, 1);
    });

    test('per-endpoint timeout override is used in effective policy', () async {
      // We can't easily test the actual timeout behavior, but we can verify
      // the endpoint is used successfully with the override
      final result = await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com', timeoutSeconds: 1),
        ],
        execute: (url) => Future.value('ok'),
        classifyError: (_) => ErrorDisposition.retry,
      );
      expect(result, 'ok');
    });

    test('disabled endpoints skipped', () async {
      final urlsSeen = <String>[];

      final result = await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'disabled', name: 'Disabled', url: 'https://disabled.com', enabled: false),
          ServiceEndpoint(id: 'enabled', name: 'Enabled', url: 'https://enabled.com'),
        ],
        execute: (url) {
          urlsSeen.add(url);
          return Future.value('ok');
        },
        classifyError: (_) => ErrorDisposition.retry,
      );

      expect(result, 'ok');
      expect(urlsSeen, ['https://enabled.com']);
    });

    test('all endpoints fail rethrows last error', () async {
      await expectLater(
        () => executeWithEndpointList<String>(
          endpoints: const [
            ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
            ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
          ],
          execute: (url) {
            if (url == 'https://b.com') throw Exception('b failed');
            throw Exception('a failed');
          },
          classifyError: (_) => ErrorDisposition.retry,
          defaultPolicy: const ResiliencePolicy(
            maxRetries: 0,
            retryBackoffBase: Duration.zero,
          ),
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(), 'message', contains('b failed'),
        )),
      );
    });

    test('3 endpoints, first 2 fail, third succeeds', () async {
      final urlsSeen = <String>[];

      final result = await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
          ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
          ServiceEndpoint(id: 'c', name: 'C', url: 'https://c.com'),
        ],
        execute: (url) {
          urlsSeen.add(url);
          if (url == 'https://c.com') return Future.value('ok from c');
          throw Exception('fail');
        },
        classifyError: (_) => ErrorDisposition.retry,
        defaultPolicy: const ResiliencePolicy(
          maxRetries: 0,
          retryBackoffBase: Duration.zero,
        ),
      );

      expect(result, 'ok from c');
      expect(urlsSeen, ['https://a.com', 'https://b.com', 'https://c.com']);
    });
  });

  group('ResilienceMetrics', () {
    setUp(() {
      ResilienceMetrics().reset();
    });

    test('records primary success via endpoint list', () async {
      await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
        ],
        execute: (_) => Future.value('ok'),
        classifyError: (_) => ErrorDisposition.retry,
      );

      final m = ResilienceMetrics();
      expect(m.totalRequests, 1);
      expect(m.primarySuccesses, 1);
      expect(m.fallbackSuccesses, 0);
      expect(m.totalRetries, 0);
      expect(m.fallbackInvocations, 0);
      expect(m.aborts, 0);
      expect(m.totalFailures, 0);
    });

    test('records fallback success via endpoint list', () async {
      await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
          ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
        ],
        execute: (url) {
          if (url == 'https://a.com') throw Exception('down');
          return Future.value('ok');
        },
        classifyError: (_) => ErrorDisposition.fallback,
        defaultPolicy: const ResiliencePolicy(
          maxRetries: 0,
          retryBackoffBase: Duration.zero,
        ),
      );

      final m = ResilienceMetrics();
      expect(m.totalRequests, 1);
      expect(m.primarySuccesses, 0);
      expect(m.fallbackSuccesses, 1);
      expect(m.fallbackInvocations, 1);
    });

    test('records retries on transient failure then success', () async {
      int callCount = 0;
      await executeWithEndpointList<String>(
        endpoints: const [
          ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
        ],
        execute: (_) {
          callCount++;
          if (callCount < 3) throw Exception('transient');
          return Future.value('ok');
        },
        classifyError: (_) => ErrorDisposition.retry,
        defaultPolicy: const ResiliencePolicy(
          maxRetries: 2,
          retryBackoffBase: Duration.zero,
        ),
      );

      final m = ResilienceMetrics();
      expect(m.totalRequests, 1);
      expect(m.primarySuccesses, 1);
      expect(m.totalRetries, 2);
    });

    test('records abort via endpoint list', () async {
      try {
        await executeWithEndpointList<String>(
          endpoints: const [
            ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
            ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
          ],
          execute: (_) => throw Exception('bad request'),
          classifyError: (_) => ErrorDisposition.abort,
        );
      } catch (_) {}

      final m = ResilienceMetrics();
      expect(m.totalRequests, 1);
      expect(m.aborts, 1);
      expect(m.fallbackInvocations, 0);
      expect(m.totalFailures, 0);
    });

    test('records total failure when all endpoints fail', () async {
      try {
        await executeWithEndpointList<String>(
          endpoints: const [
            ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
            ServiceEndpoint(id: 'b', name: 'B', url: 'https://b.com'),
          ],
          execute: (_) => throw Exception('down'),
          classifyError: (_) => ErrorDisposition.retry,
          defaultPolicy: const ResiliencePolicy(
            maxRetries: 0,
            retryBackoffBase: Duration.zero,
          ),
        );
      } catch (_) {}

      final m = ResilienceMetrics();
      expect(m.totalRequests, 1);
      expect(m.fallbackInvocations, 1);
      expect(m.totalFailures, 1);
      expect(m.primarySuccesses, 0);
      expect(m.fallbackSuccesses, 0);
    });

    test('records error types', () async {
      try {
        await executeWithEndpointList<String>(
          endpoints: const [
            ServiceEndpoint(id: 'a', name: 'A', url: 'https://a.com'),
          ],
          execute: (_) => throw FormatException('bad'),
          classifyError: (_) => ErrorDisposition.abort,
        );
      } catch (_) {}

      final m = ResilienceMetrics();
      expect(m.errorsByType['FormatException'], 1);
    });

    test('summary is human-readable', () {
      final m = ResilienceMetrics();
      expect(m.summary, contains('requests:'));
      expect(m.summary, contains('primaryOk:'));
      expect(m.summary, contains('avgLatency:'));
    });
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/services/overpass_service.dart';
import 'package:deflockapp/services/node_data_manager.dart';
import 'package:deflockapp/services/node_spatial_cache.dart';

class MockOverpassService extends Mock implements OverpassService {}

class MockNodeSpatialCache extends Mock implements NodeSpatialCache {}

class MockHttpClient extends Mock implements http.Client {}

void main() {
  final testBounds = LatLngBounds(
    const LatLng(38.0, -78.0),
    const LatLng(39.0, -77.0),
  );

  final testProfiles = [
    NodeProfile(
      id: 'test',
      name: 'Test Profile',
      tags: const {'man_made': 'surveillance'},
    ),
  ];

  OsmNode makeNode(int id, {double lat = 38.5, double lng = -77.5}) => OsmNode(
    id: id,
    coord: LatLng(lat, lng),
    tags: const {'man_made': 'surveillance'},
  );

  setUpAll(() {
    registerFallbackValue(testBounds);
    registerFallbackValue(<NodeProfile>[]);
    registerFallbackValue(<OsmNode>[]);
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(const Duration(seconds: 1));
  });

  group('splitBounds', () {
    test('splits into 4 correct quadrants with center at midpoint', () {
      final bounds = LatLngBounds(
        const LatLng(0.0, 0.0),
        const LatLng(10.0, 10.0),
      );

      final quadrants = NodeDataManager.splitBounds(bounds);

      expect(quadrants, hasLength(4));

      // Southwest
      expect(quadrants[0].south, 0.0);
      expect(quadrants[0].west, 0.0);
      expect(quadrants[0].north, 5.0);
      expect(quadrants[0].east, 5.0);

      // Southeast
      expect(quadrants[1].south, 0.0);
      expect(quadrants[1].west, 5.0);
      expect(quadrants[1].north, 5.0);
      expect(quadrants[1].east, 10.0);

      // Northwest
      expect(quadrants[2].south, 5.0);
      expect(quadrants[2].west, 0.0);
      expect(quadrants[2].north, 10.0);
      expect(quadrants[2].east, 5.0);

      // Northeast
      expect(quadrants[3].south, 5.0);
      expect(quadrants[3].west, 5.0);
      expect(quadrants[3].north, 10.0);
      expect(quadrants[3].east, 10.0);
    });

    test('quadrants tile exactly - no gaps or overlaps', () {
      final bounds = LatLngBounds(
        const LatLng(10.0, 20.0),
        const LatLng(30.0, 40.0),
      );

      final quadrants = NodeDataManager.splitBounds(bounds);

      // Total area should equal original
      final totalLatSpan = quadrants.map((q) => q.north - q.south).reduce((a, b) => a + b);
      final totalLngSpan = quadrants.map((q) => q.east - q.west).reduce((a, b) => a + b);

      // Each quadrant is half the span, and we have 4 quadrants (2x2)
      // Total lat span = 2 * half = full span
      expect(totalLatSpan, closeTo((bounds.north - bounds.south) * 2, 1e-10));
      expect(totalLngSpan, closeTo((bounds.east - bounds.west) * 2, 1e-10));

      // Verify edges align at center
      final centerLat = (bounds.north + bounds.south) / 2;
      final centerLng = (bounds.east + bounds.west) / 2;

      for (final q in quadrants) {
        // Every quadrant edge should be either an original edge or the center
        expect(
          q.south == bounds.south || q.south == centerLat,
          isTrue,
          reason: 'south edge ${q.south} should be original south or center',
        );
        expect(
          q.north == bounds.north || q.north == centerLat,
          isTrue,
          reason: 'north edge ${q.north} should be original north or center',
        );
        expect(
          q.west == bounds.west || q.west == centerLng,
          isTrue,
          reason: 'west edge ${q.west} should be original west or center',
        );
        expect(
          q.east == bounds.east || q.east == centerLng,
          isTrue,
          reason: 'east edge ${q.east} should be original east or center',
        );
      }
    });
  });

  group('OverpassService.getSlotCount', () {
    late MockHttpClient mockClient;
    late OverpassService service;

    setUp(() {
      mockClient = MockHttpClient();
      service = OverpassService(client: mockClient);
    });

    test('parses Rate limit from status response', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(
          'Connected as: 123456\n'
          'Current time: 2025-01-01T00:00:00Z\n'
          'Rate limit: 6\n'
          '2 slots available now.',
          200,
        ),
      );

      final count = await service.getSlotCount();
      expect(count, 6);
    });

    test('falls back to defaultSlotCount on HTTP failure', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response('Server Error', 500),
      );

      final count = await service.getSlotCount();
      expect(count, OverpassService.defaultSlotCount);
    });

    test('falls back to defaultSlotCount on network error', () async {
      when(() => mockClient.get(any())).thenThrow(
        http.ClientException('Connection refused'),
      );

      final count = await service.getSlotCount();
      expect(count, OverpassService.defaultSlotCount);
    });
  });

  group('OverpassService.waitForSlot', () {
    late MockHttpClient mockClient;
    late OverpassService service;

    setUp(() {
      mockClient = MockHttpClient();
      service = OverpassService(client: mockClient);
    });

    test('returns immediately when slots available now', () async {
      when(() => mockClient.get(any())).thenAnswer(
        (_) async => http.Response(
          'Rate limit: 6\n2 slots available now.',
          200,
        ),
      );

      final slots = await service.waitForSlot();
      expect(slots, 6);
      verify(() => mockClient.get(any())).called(1);
    });

    test('waits and re-polls when "in N seconds" in response', () {
      FakeAsync().run((fake) {
        var fakeElapsed = Duration.zero;
        var callCount = 0;
        when(() => mockClient.get(any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              'Rate limit: 4\nSlot available after: 2025-01-01T00:00:03Z, in 1 seconds.',
              200,
            );
          }
          return http.Response(
            'Rate limit: 4\n2 slots available now.',
            200,
          );
        });

        late int slots;
        service.waitForSlot(elapsedFn: () => fakeElapsed).then((s) => slots = s);

        fakeElapsed = const Duration(seconds: 1);
        fake.elapse(const Duration(seconds: 2));

        expect(slots, 4);
        expect(callCount, 2);
      });
    });

    test('falls back to 5s poll on unparseable response', () {
      FakeAsync().run((fake) {
        var fakeElapsed = Duration.zero;
        var callCount = 0;
        when(() => mockClient.get(any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return http.Response('some garbage response', 200);
          }
          return http.Response(
            'Rate limit: 4\n1 slots available now.',
            200,
          );
        });

        late int slots;
        service.waitForSlot(elapsedFn: () => fakeElapsed).then((s) => slots = s);

        fakeElapsed = const Duration(seconds: 5);
        fake.elapse(const Duration(seconds: 6));

        expect(slots, 4);
        expect(callCount, 2);
      });
    });

    test('returns updated slot count if Rate limit changes', () {
      FakeAsync().run((fake) {
        var fakeElapsed = Duration.zero;
        var callCount = 0;
        when(() => mockClient.get(any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              'Rate limit: 4\nSlot available after: ..., in 1 seconds.',
              200,
            );
          }
          return http.Response(
            'Rate limit: 8\n3 slots available now.',
            200,
          );
        });

        late int slots;
        service.waitForSlot(elapsedFn: () => fakeElapsed).then((s) => slots = s);

        fakeElapsed = const Duration(seconds: 1);
        fake.elapse(const Duration(seconds: 2));

        expect(slots, 8);
      });
    });

    test('returns default slot count when maxWait deadline expires', () {
      FakeAsync().run((fake) {
        var fakeElapsed = Duration.zero;
        when(() => mockClient.get(any())).thenAnswer(
          (_) async => http.Response('Rate limit: 6\nNo slots right now.', 200),
        );

        late int slots;
        service.waitForSlot(
          maxWait: const Duration(seconds: 10),
          elapsedFn: () => fakeElapsed,
        ).then((s) => slots = s);

        // Advance past maxWait
        fakeElapsed = const Duration(seconds: 11);
        fake.elapse(const Duration(seconds: 6));

        expect(slots, 6);
      });
    });
  });

  group('fetchWithSplitting', () {
    late MockOverpassService mockOverpass;
    late MockNodeSpatialCache mockCache;
    late NodeDataManager manager;

    setUp(() {
      mockOverpass = MockOverpassService();
      mockCache = MockNodeSpatialCache();
      manager = NodeDataManager.forTesting(
        overpassService: mockOverpass,
        cache: mockCache,
      );

      // Default: semaphore init returns 4 slots
      when(() => mockOverpass.getSlotCount()).thenAnswer((_) async => 4);

      // Default: cache operations are no-ops
      when(() => mockCache.markAreaAsFetched(any(), any())).thenReturn(null);
    });

    test('happy path - returns nodes and caches them', () async {
      final nodes = [makeNode(1), makeNode(2)];

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async => nodes);

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      expect(result, hasLength(2));
      verify(() => mockCache.markAreaAsFetched(any(), any())).called(1);
    });

    test('NodeLimitError splits into 4 and combines results', () async {
      var callCount = 0;

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw NodeLimitError('too many nodes');
        }
        return [makeNode(callCount)];
      });

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      // First call throws, then 4 quadrant calls succeed
      expect(result, hasLength(4));
      verify(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).called(5); // 1 initial + 4 quadrants
    });

    test('max depth + NodeLimitError returns empty', () async {
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenThrow(NodeLimitError('too many nodes'));

      final result = await manager.fetchWithSplitting(
        testBounds, testProfiles,
        splitDepth: 3,
      );

      expect(result, isEmpty);
    });

    test('RateLimitError polls for slot, resizes semaphore, retries', () async {
      var callCount = 0;

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw RateLimitError('rate limited');
        }
        return [makeNode(1)];
      });

      when(() => mockOverpass.waitForSlot(maxWait: any(named: 'maxWait')))
          .thenAnswer((_) async => 6);

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      expect(result, hasLength(1));
      verify(() => mockOverpass.waitForSlot(maxWait: any(named: 'maxWait'))).called(1);
    });

    test('RateLimitError x3 gives up after 2 retries', () async {
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenThrow(RateLimitError('rate limited'));

      when(() => mockOverpass.waitForSlot(maxWait: any(named: 'maxWait')))
          .thenAnswer((_) async => 4);

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      expect(result, isEmpty);
      // Called twice (retry 1 and retry 2), third attempt gives up
      verify(() => mockOverpass.waitForSlot(maxWait: any(named: 'maxWait'))).called(2);
    });
  });

  group('_fetchSplitAreas (via fetchWithSplitting)', () {
    late MockOverpassService mockOverpass;
    late MockNodeSpatialCache mockCache;
    late NodeDataManager manager;

    setUp(() {
      mockOverpass = MockOverpassService();
      mockCache = MockNodeSpatialCache();
      manager = NodeDataManager.forTesting(
        overpassService: mockOverpass,
        cache: mockCache,
      );

      when(() => mockOverpass.getSlotCount()).thenAnswer((_) async => 4);
      when(() => mockCache.markAreaAsFetched(any(), any())).thenReturn(null);
    });

    test('partial failure - 1 quadrant throws, other 3 return nodes', () async {
      var callCount = 0;

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          // Initial call: trigger split
          throw NodeLimitError('too many nodes');
        }
        if (callCount == 2) {
          // First quadrant: network error
          throw NetworkError('connection failed');
        }
        // Other 3 quadrants succeed
        return [makeNode(callCount)];
      });

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      // 3 of 4 quadrants returned 1 node each
      expect(result, hasLength(3));
    });

    test('all quadrants fail returns empty', () async {
      var callCount = 0;

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw NodeLimitError('too many nodes');
        }
        throw NetworkError('connection failed');
      });

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);
      expect(result, isEmpty);
    });

    test('recursive splitting - depth-1 NodeLimitError, depth-2 success', () async {
      var callCount = 0;

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        callCount++;
        // First 5 calls all hit node limit (1 initial + 4 quadrants at depth 1)
        if (callCount <= 5) {
          throw NodeLimitError('too many nodes');
        }
        // Depth-2 calls succeed
        return [makeNode(callCount)];
      });

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      // 4 quadrants at depth 1 each split into 4 = 16 depth-2 fetches
      expect(result, hasLength(16));
    });
  });

  group('semaphore initialization', () {
    late MockOverpassService mockOverpass;
    late MockNodeSpatialCache mockCache;
    late NodeDataManager manager;

    setUp(() {
      mockOverpass = MockOverpassService();
      mockCache = MockNodeSpatialCache();
      manager = NodeDataManager.forTesting(
        overpassService: mockOverpass,
        cache: mockCache,
      );

      when(() => mockCache.markAreaAsFetched(any(), any())).thenReturn(null);
    });

    test('concurrent calls to semaphore init return same instance', () async {
      var getSlotCallCount = 0;
      when(() => mockOverpass.getSlotCount()).thenAnswer((_) async {
        getSlotCallCount++;
        // Simulate slow network
        await Future.delayed(const Duration(milliseconds: 10));
        return 4;
      });

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async => [makeNode(1)]);

      // Launch two concurrent fetches
      final results = await Future.wait([
        manager.fetchWithSplitting(testBounds, testProfiles),
        manager.fetchWithSplitting(testBounds, testProfiles),
      ]);

      // Both should succeed
      expect(results[0], hasLength(1));
      expect(results[1], hasLength(1));

      // getSlotCount should only be called once (shared init future)
      expect(getSlotCallCount, 1);
    });
  });
}

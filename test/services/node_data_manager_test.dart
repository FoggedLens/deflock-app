import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
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

      // Summing all quadrant spans gives 2x original (2 rows + 2 columns of half-spans)
      final totalLatSpan = quadrants.map((q) => q.north - q.south).reduce((a, b) => a + b);
      final totalLngSpan = quadrants.map((q) => q.east - q.west).reduce((a, b) => a + b);
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

    test('RateLimitError is rethrown for reconciliation to handle', () async {
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenThrow(RateLimitError('rate limited'));

      expect(
        () => manager.fetchWithSplitting(testBounds, testProfiles),
        throwsA(isA<RateLimitError>()),
      );
    });

    test('RateLimitError carries waitSeconds from pre-flight', () async {
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenThrow(RateLimitError('rate limited', waitSeconds: 14));

      try {
        await manager.fetchWithSplitting(testBounds, testProfiles);
        fail('should have thrown');
      } on RateLimitError catch (e) {
        expect(e.waitSeconds, 14);
      }
    });

    test('RateLimitError in quadrant fetch propagates instead of being swallowed', () async {
      var callCount = 0;
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw NodeLimitError('too many nodes');
        }
        // First quadrant succeeds, second hits rate limit
        if (callCount == 3) {
          throw RateLimitError('rate limited', waitSeconds: 10);
        }
        return [makeNode(callCount)];
      });

      expect(
        () => manager.fetchWithSplitting(testBounds, testProfiles),
        throwsA(isA<RateLimitError>()),
      );
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
      // Track split depth via bounds size to determine behavior
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((invocation) async {
        final bounds = invocation.namedArguments[#bounds] as LatLngBounds;
        final latSpan = bounds.north - bounds.south;
        // Original expanded bounds have ~1.2x span; depth-1 quadrants are ~half
        // Depth-0 and depth-1 hit node limit; depth-2 succeeds
        if (latSpan > 0.3) {
          throw NodeLimitError('too many nodes');
        }
        return [makeNode(bounds.hashCode)];
      });

      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      // 4 quadrants at depth 1 each split into 4 = 16 depth-2 fetches
      expect(result, hasLength(16));
    });
  });

  group('stale fetch cancellation', () {
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

    test('stale generation skips fetch entirely', () async {
      manager.advanceFetchGeneration();

      final result = await manager.fetchWithSplitting(
        testBounds, testProfiles,
        generation: 0,
      );

      expect(result, isEmpty);
      verifyNever(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      ));
    });

    test('stale generation inside semaphore lambda prevents HTTP call', () async {
      // Saturate the semaphore (2 slots) so the third request waits
      final completer1 = Completer<List<OsmNode>>();
      final completer2 = Completer<List<OsmNode>>();
      var fetchCallCount = 0;

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) {
        fetchCallCount++;
        if (fetchCallCount == 1) return completer1.future;
        if (fetchCallCount == 2) return completer2.future;
        return Future.value([makeNode(fetchCallCount)]);
      });

      // Launch two requests to fill both semaphore slots
      final future1 = manager.fetchWithSplitting(testBounds, testProfiles);
      final future2 = manager.fetchWithSplitting(testBounds, testProfiles);
      await Future.delayed(Duration.zero); // Let them enter the semaphore

      // Third request will queue in semaphore
      final future3 = manager.fetchWithSplitting(
        testBounds, testProfiles,
        generation: 0,
      );

      // Advance generation while third request is queued
      manager.advanceFetchGeneration();

      // Release first two
      completer1.complete([makeNode(1)]);
      completer2.complete([makeNode(2)]);
      await future1;
      await future2;

      // Third request wakes up but is stale — should skip HTTP call
      final result3 = await future3;
      expect(result3, isEmpty);
      // Only 2 HTTP calls (from the first two), not 3
      expect(fetchCallCount, 2);
    });

    test('stale generation prevents recursive splitting', () async {
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        manager.advanceFetchGeneration();
        throw NodeLimitError('too many nodes');
      });

      final result = await manager.fetchWithSplitting(
        testBounds, testProfiles,
        generation: 0,
      );

      expect(result, isEmpty);
      // Only the initial call, no quadrant fetches
      verify(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).called(1);
    });

    test('null generation is never stale (backward compat)', () async {
      final nodes = [makeNode(1), makeNode(2)];

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async => nodes);

      // Advance generation many times
      for (var i = 0; i < 10; i++) {
        manager.advanceFetchGeneration();
      }

      // Call without generation parameter — null generation is never stale
      final result = await manager.fetchWithSplitting(testBounds, testProfiles);

      expect(result, hasLength(2));
      verify(() => mockCache.markAreaAsFetched(any(), any())).called(1);
    });
  });

  group('progressive rendering (throttled)', () {
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

    test('rapid quadrant completions are batched into one notification', () {
      FakeAsync().run((fake) {
        var notifyCount = 0;
        manager.addListener(() => notifyCount++);

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

        late List<OsmNode> result;
        manager.fetchWithSplitting(testBounds, testProfiles).then((r) => result = r);

        // Let all futures complete
        fake.elapse(Duration.zero);
        expect(result, hasLength(4));

        // No notifications yet — throttle timer is pending
        expect(notifyCount, 0);

        // After 200ms throttle window, one batched notification fires
        fake.elapse(const Duration(milliseconds: 200));
        expect(notifyCount, 1);
      });
    });

    test('empty quadrant results do not trigger notification', () {
      FakeAsync().run((fake) {
        var notifyCount = 0;
        manager.addListener(() => notifyCount++);

        var callCount = 0;
        when(() => mockOverpass.fetchNodes(
          bounds: any(named: 'bounds'),
          profiles: any(named: 'profiles'),
        )).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            throw NodeLimitError('too many nodes');
          }
          // All quadrants return empty
          return <OsmNode>[];
        });

        late List<OsmNode> result;
        manager.fetchWithSplitting(testBounds, testProfiles).then((r) => result = r);

        fake.elapse(Duration.zero);
        expect(result, isEmpty);

        // No notifications even after throttle window — no nodes to render
        fake.elapse(const Duration(milliseconds: 200));
        expect(notifyCount, 0);
      });
    });
  });

  group('semaphore concurrency', () {
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

    test('semaphore allows up to 2 concurrent Overpass requests', () async {
      var concurrentCount = 0;
      var maxConcurrent = 0;

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        concurrentCount++;
        if (concurrentCount > maxConcurrent) maxConcurrent = concurrentCount;
        await Future.delayed(const Duration(milliseconds: 10));
        concurrentCount--;
        return [makeNode(1)];
      });

      // Three concurrent user-initiated fetches — semaphore limits to 2 (Overpass slot count)
      await Future.wait([
        manager.fetchWithSplitting(testBounds, testProfiles, isUserInitiated: true),
        manager.fetchWithSplitting(testBounds, testProfiles, isUserInitiated: true),
        manager.fetchWithSplitting(testBounds, testProfiles, isUserInitiated: true),
      ]);

      expect(maxConcurrent, 2);
      // All three completed (3 HTTP calls total)
      verify(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).called(3);
    });

    test('priority request jumps ahead of background requests in queue', () async {
      // Use completers so we control exactly when slot-fillers finish
      final slotBlockers = [Completer<void>(), Completer<void>()];
      final completionOrder = <String>[];

      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        return [makeNode(1)];
      });

      // Wrap fetchNodes to block slot-fillers
      var callCount = 0;
      when(() => mockOverpass.fetchNodes(
        bounds: any(named: 'bounds'),
        profiles: any(named: 'profiles'),
      )).thenAnswer((_) async {
        final idx = callCount++;
        if (idx < 2) {
          await slotBlockers[idx].future;
        }
        return [makeNode(idx)];
      });

      // Fill both semaphore slots
      final bg1 = manager.fetchWithSplitting(testBounds, testProfiles, isUserInitiated: true);
      final bg2 = manager.fetchWithSplitting(testBounds, testProfiles, isUserInitiated: true);

      // Queue background FIRST, then priority — priority should still run first
      final bg3 = manager.fetchWithSplitting(testBounds, testProfiles)
          .then((_) => completionOrder.add('background'));
      final priority = manager.fetchWithSplitting(testBounds, testProfiles, isUserInitiated: true)
          .then((_) => completionOrder.add('priority'));

      // Release both slots
      slotBlockers[0].complete();
      slotBlockers[1].complete();

      await Future.wait([bg1, bg2, bg3, priority]);

      // Priority was queued second but should have completed first
      expect(completionOrder.indexOf('priority'), lessThan(completionOrder.indexOf('background')),
          reason: 'Priority request should complete before background request');
    });
  });

  group('hasFreshDataFor', () {
    test('returns true for recently cached area', () {
      final cache = NodeSpatialCache.forTesting();
      final bounds = LatLngBounds(const LatLng(38, -78), const LatLng(39, -77));
      cache.markAreaAsFetched(bounds, [makeNode(1)]);
      expect(cache.hasFreshDataFor(bounds), isTrue);
    });

    test('returns false for uncached area', () {
      final cache = NodeSpatialCache.forTesting();
      final bounds = LatLngBounds(const LatLng(38, -78), const LatLng(39, -77));
      expect(cache.hasFreshDataFor(bounds), isFalse);
    });

    test('returns true for sub-bounds of cached area', () {
      final cache = NodeSpatialCache.forTesting();
      final outer = LatLngBounds(const LatLng(37, -79), const LatLng(40, -76));
      final inner = LatLngBounds(const LatLng(38, -78), const LatLng(39, -77));
      cache.markAreaAsFetched(outer, [makeNode(1)]);
      expect(cache.hasFreshDataFor(inner), isTrue);
    });
  });

  group('fetchedAreas', () {
    test('returns empty list for fresh cache', () {
      final cache = NodeSpatialCache.forTesting();
      final manager = NodeDataManager.forTesting(cache: cache);
      expect(manager.fetchedAreas, isEmpty);
    });

    test('returns areas with timestamps after marking as fetched', () {
      final cache = NodeSpatialCache.forTesting();
      final manager = NodeDataManager.forTesting(cache: cache);

      final bounds1 = LatLngBounds(const LatLng(38, -78), const LatLng(39, -77));
      final bounds2 = LatLngBounds(const LatLng(40, -76), const LatLng(41, -75));
      cache.markAreaAsFetched(bounds1, [makeNode(1)]);
      cache.markAreaAsFetched(bounds2, [makeNode(2)]);

      final areas = manager.fetchedAreas;
      expect(areas, hasLength(2));
      expect(areas[0].bounds, bounds1);
      expect(areas[1].bounds, bounds2);
      // Timestamps should be recent
      final now = DateTime.now();
      expect(now.difference(areas[0].fetchedAt).inSeconds, lessThan(5));
      expect(now.difference(areas[1].fetchedAt).inSeconds, lessThan(5));
    });
  });
}

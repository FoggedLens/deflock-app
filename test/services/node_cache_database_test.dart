import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/services/node_cache_database.dart';
import 'package:deflockapp/services/node_data_manager.dart';
import 'package:deflockapp/services/node_spatial_cache.dart';

void main() {
  // Use FFI for headless SQLite testing
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late NodeCacheDatabase db;

  setUp(() async {
    db = NodeCacheDatabase.forTesting();
    await db.init();
    await db.clearAll();
  });

  tearDown(() async {
    await db.close();
  });

  final testBounds = LatLngBounds(
    const LatLng(38.0, -78.0),
    const LatLng(39.0, -77.0),
  );

  OsmNode makeNode(int id, {
    double lat = 38.5,
    double lng = -77.5,
    Map<String, String> tags = const {'man_made': 'surveillance'},
    bool isConstrained = false,
  }) => OsmNode(
    id: id,
    coord: LatLng(lat, lng),
    tags: tags,
    isConstrained: isConstrained,
  );

  group('node insert/load round-trip', () {
    test('inserts and loads nodes with correct data', () async {
      final nodes = [
        makeNode(1, tags: {'man_made': 'surveillance', 'operator': 'city'}),
        makeNode(2, lat: 38.6, lng: -77.6, isConstrained: true),
      ];

      await db.insertNodes(nodes);
      final loaded = await db.loadAllNodes();

      expect(loaded, hasLength(2));

      final node1 = loaded.firstWhere((n) => n.id == 1);
      expect(node1.coord.latitude, 38.5);
      expect(node1.coord.longitude, -77.5);
      expect(node1.tags['man_made'], 'surveillance');
      expect(node1.tags['operator'], 'city');
      expect(node1.isConstrained, false);

      final node2 = loaded.firstWhere((n) => n.id == 2);
      expect(node2.coord.latitude, 38.6);
      expect(node2.coord.longitude, -77.6);
      expect(node2.isConstrained, true);
    });

    test('upserts replace existing nodes', () async {
      await db.insertNodes([makeNode(1, tags: {'version': '1'})]);
      await db.insertNodes([makeNode(1, tags: {'version': '2'})]);

      final loaded = await db.loadAllNodes();
      expect(loaded, hasLength(1));
      expect(loaded.first.tags['version'], '2');
    });
  });

  group('negative ID filtering', () {
    test('does not persist negative-ID nodes', () async {
      final nodes = [
        makeNode(-1),
        makeNode(-999),
        makeNode(1),
        makeNode(42),
      ];

      await db.insertNodes(nodes);
      final loaded = await db.loadAllNodes();

      expect(loaded, hasLength(2));
      expect(loaded.map((n) => n.id).toSet(), {1, 42});
    });
  });

  group('underscore tag stripping', () {
    test('strips underscore-prefixed tags before persisting', () async {
      final node = makeNode(1, tags: {
        'man_made': 'surveillance',
        '_pending_edit': 'true',
        '_pending_deletion': 'true',
        'operator': 'city',
      });

      await db.insertNodes([node]);
      final loaded = await db.loadAllNodes();

      expect(loaded, hasLength(1));
      expect(loaded.first.tags.containsKey('_pending_edit'), false);
      expect(loaded.first.tags.containsKey('_pending_deletion'), false);
      expect(loaded.first.tags['man_made'], 'surveillance');
      expect(loaded.first.tags['operator'], 'city');
    });
  });

  group('cached area insert/load round-trip', () {
    test('inserts and loads cached areas within TTL', () async {
      final now = DateTime.now();
      await db.insertCachedArea(testBounds, now);

      final loaded = await db.loadCachedAreas(ttl: const Duration(days: 7));

      expect(loaded, hasLength(1));
      expect(loaded.first.bounds.south, testBounds.south);
      expect(loaded.first.bounds.west, testBounds.west);
      expect(loaded.first.bounds.north, testBounds.north);
      expect(loaded.first.bounds.east, testBounds.east);
    });

    test('does not load areas past TTL', () async {
      final old = DateTime.now().subtract(const Duration(days: 8));
      await db.insertCachedArea(testBounds, old);

      final loaded = await db.loadCachedAreas(ttl: const Duration(days: 7));
      expect(loaded, isEmpty);
    });
  });

  group('TTL expiration pruning', () {
    test('deleteExpiredData removes expired areas', () async {
      final old = DateTime.now().subtract(const Duration(days: 8));
      final fresh = DateTime.now();

      final bounds2 = LatLngBounds(
        const LatLng(40.0, -76.0),
        const LatLng(41.0, -75.0),
      );

      await db.insertCachedArea(testBounds, old);
      await db.insertCachedArea(bounds2, fresh);

      await db.deleteExpiredData(ttl: const Duration(days: 7));

      final loaded = await db.loadCachedAreas(ttl: const Duration(days: 7));
      expect(loaded, hasLength(1));
      expect(loaded.first.bounds.south, bounds2.south);
    });
  });

  group('orphaned node cleanup', () {
    test('deletes nodes not covered by any remaining area', () async {
      final old = DateTime.now().subtract(const Duration(days: 8));
      final fresh = DateTime.now();

      final freshBounds = LatLngBounds(
        const LatLng(40.0, -76.0),
        const LatLng(41.0, -75.0),
      );

      // Node in expired area only
      await db.insertNodes([makeNode(1, lat: 38.5, lng: -77.5)]);
      await db.insertCachedArea(testBounds, old);

      // Node in fresh area
      await db.insertNodes([makeNode(2, lat: 40.5, lng: -75.5)]);
      await db.insertCachedArea(freshBounds, fresh);

      await db.deleteExpiredData(ttl: const Duration(days: 7));

      final loaded = await db.loadAllNodes();
      expect(loaded, hasLength(1));
      expect(loaded.first.id, 2);
    });

    test('deletes all nodes when all areas expire', () async {
      final old = DateTime.now().subtract(const Duration(days: 8));

      await db.insertNodes([makeNode(1), makeNode(2)]);
      await db.insertCachedArea(testBounds, old);

      await db.deleteExpiredData(ttl: const Duration(days: 7));

      final loaded = await db.loadAllNodes();
      expect(loaded, isEmpty);
    });
  });

  group('clearAll', () {
    test('wipes all nodes and areas', () async {
      await db.insertNodes([makeNode(1), makeNode(2)]);
      await db.insertCachedArea(testBounds, DateTime.now());

      await db.clearAll();

      expect(await db.loadAllNodes(), isEmpty);
      expect(
        await db.loadCachedAreas(ttl: const Duration(days: 7)),
        isEmpty,
      );
    });
  });

  group('staleAreaFor', () {
    test('returns null when no coverage', () {
      final cache = NodeSpatialCache.forTesting();
      expect(cache.staleAreaFor(testBounds), isNull);
    });

    test('returns null for fresh data', () {
      final cache = NodeSpatialCache.forTesting();
      cache.markAreaAsFetched(testBounds, [makeNode(1)]);
      expect(cache.staleAreaFor(testBounds), isNull);
    });

    test('freshThreshold is 1 hour', () {
      // Verify the threshold constant so stale logic is correct
      expect(NodeSpatialCache.freshThreshold, const Duration(hours: 1));
    });
  });

  group('ring cell generation', () {
    test('ring 1 produces 8 cells', () {
      final viewport = LatLngBounds(
        const LatLng(0.0, 0.0),
        const LatLng(1.0, 1.0),
      );

      final cells = NodeDataManager.generateRingCells(viewport, 1);
      expect(cells, hasLength(8));
    });

    test('ring 2 produces 8 + 16 = 24 cells', () {
      final viewport = LatLngBounds(
        const LatLng(0.0, 0.0),
        const LatLng(1.0, 1.0),
      );

      final cells = NodeDataManager.generateRingCells(viewport, 2);
      expect(cells, hasLength(24)); // 8 + 16
    });

    test('ring 3 produces 8 + 16 + 24 = 48 cells', () {
      final viewport = LatLngBounds(
        const LatLng(0.0, 0.0),
        const LatLng(1.0, 1.0),
      );

      final cells = NodeDataManager.generateRingCells(viewport, 3);
      expect(cells, hasLength(48));
    });

    test('cells are viewport-sized', () {
      final viewport = LatLngBounds(
        const LatLng(10.0, 20.0),
        const LatLng(12.0, 23.0),
      );

      final cells = NodeDataManager.generateRingCells(viewport, 1);

      for (final cell in cells) {
        expect(cell.north - cell.south, closeTo(2.0, 1e-10));
        expect(cell.east - cell.west, closeTo(3.0, 1e-10));
      }
    });
  });
}

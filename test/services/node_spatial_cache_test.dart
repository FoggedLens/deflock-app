import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/services/node_spatial_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('NodeSpatialCache constrained flag', () {
    setUp(() {
      // NodeSpatialCache is a singleton - start each test from a clean slate.
      NodeSpatialCache().clear();
    });

    test('stays constrained after an update that omits the flag', () {
      final cache = NodeSpatialCache();
      const nodeId = 123;

      cache.addOrUpdateNodes([
        OsmNode(
          id: nodeId,
          coord: const LatLng(0, 0),
          tags: const {},
          isConstrained: true,
        ),
      ]);

      // Simulate what happens after an edit upload succeeds: a brand-new
      // OsmNode is built from upload data, which has no way/relation
      // information and so defaults isConstrained to false.
      cache.addOrUpdateNodes([
        OsmNode(
          id: nodeId,
          coord: const LatLng(1, 1),
          tags: const {'amenity': 'surveillance'},
        ),
      ]);

      final updated = cache.getNodeById(nodeId);
      expect(updated, isNotNull);
      expect(updated!.isConstrained, isTrue);
      // Non-constraint fields should still be updated as normal.
      expect(updated.coord, const LatLng(1, 1));
      expect(updated.tags['amenity'], 'surveillance');
    });

    test('becomes constrained if a later update says it is', () {
      final cache = NodeSpatialCache();
      const nodeId = 456;

      cache.addOrUpdateNodes([
        OsmNode(id: nodeId, coord: const LatLng(0, 0), tags: const {}),
      ]);

      cache.addOrUpdateNodes([
        OsmNode(
          id: nodeId,
          coord: const LatLng(0, 0),
          tags: const {},
          isConstrained: true,
        ),
      ]);

      expect(cache.getNodeById(nodeId)!.isConstrained, isTrue);
    });
  });
}

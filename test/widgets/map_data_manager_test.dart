import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:deflockapp/models/osm_node.dart';
import 'package:deflockapp/app_state.dart';
import 'package:deflockapp/widgets/map/map_data_manager.dart';

void main() {
  OsmNode nodeAt(int id, double lat, double lng) {
    return OsmNode(id: id, coord: LatLng(lat, lng), tags: {'surveillance': 'outdoor'});
  }

  group('Node render prioritization', () {
    late MapDataManager dataManager;
    late List<OsmNode> testNodes;

    setUp(() {
      WidgetsFlutterBinding.ensureInitialized();
      testNodes = [];
      dataManager = MapDataManager(
        getNodesForBounds: (_) => testNodes,
      );
    });

    test('closest nodes to viewport center are kept', () {
      final bounds = LatLngBounds(LatLng(38.0, -78.0), LatLng(39.0, -77.0));
      // Center is (38.5, -77.5)
      testNodes = [
        nodeAt(1, 38.9, -77.9),   // far from center
        nodeAt(2, 38.5, -77.5),   // at center
        nodeAt(3, 38.1, -77.1),   // far from center
        nodeAt(4, 38.51, -77.49), // very close to center
        nodeAt(5, 38.0, -78.0),   // corner — farthest
      ];

      final result = dataManager.getNodesForRendering(
        currentZoom: 14,
        mapBounds: bounds,
        uploadMode: UploadMode.production,
        maxNodes: 3,
      );

      expect(result.isLimitActive, isTrue);
      expect(result.nodesToRender.length, 3);
      final ids = result.nodesToRender.map((n) => n.id).toSet();
      expect(ids.contains(2), isTrue, reason: 'Node at center should be kept');
      expect(ids.contains(4), isTrue, reason: 'Node near center should be kept');
      expect(ids.contains(5), isFalse, reason: 'Node at corner should be dropped');
    });

    test('returns all nodes when under the limit', () {
      final bounds = LatLngBounds(LatLng(38.0, -78.0), LatLng(39.0, -77.0));
      testNodes = [
        nodeAt(1, 38.5, -77.5),
        nodeAt(2, 38.6, -77.6),
      ];

      final result = dataManager.getNodesForRendering(
        currentZoom: 14,
        mapBounds: bounds,
        uploadMode: UploadMode.production,
        maxNodes: 10,
      );

      expect(result.isLimitActive, isFalse);
      expect(result.nodesToRender.length, 2);
    });

    test('returns empty when below minimum zoom', () {
      final bounds = LatLngBounds(LatLng(38.0, -78.0), LatLng(39.0, -77.0));
      testNodes = [nodeAt(1, 38.5, -77.5)];

      final result = dataManager.getNodesForRendering(
        currentZoom: 5,
        mapBounds: bounds,
        uploadMode: UploadMode.production,
        maxNodes: 10,
      );

      expect(result.nodesToRender, isEmpty);
    });

    test('panning viewport changes which nodes are prioritized', () {
      final nodes = [
        nodeAt(1, 38.0, -78.0), // SW
        nodeAt(2, 38.5, -77.5), // middle
        nodeAt(3, 39.0, -77.0), // NE
      ];

      // Viewport centered near SW
      testNodes = List.from(nodes);
      final swBounds = LatLngBounds(LatLng(37.5, -78.5), LatLng(38.5, -77.5));
      final swResult = dataManager.getNodesForRendering(
        currentZoom: 14,
        mapBounds: swBounds,
        uploadMode: UploadMode.production,
        maxNodes: 1,
      );
      expect(swResult.nodesToRender.first.id, 1,
          reason: 'SW node closest to SW-centered viewport');

      // Viewport centered near NE
      testNodes = List.from(nodes);
      final neBounds = LatLngBounds(LatLng(38.5, -77.5), LatLng(39.5, -76.5));
      final neResult = dataManager.getNodesForRendering(
        currentZoom: 14,
        mapBounds: neBounds,
        uploadMode: UploadMode.production,
        maxNodes: 1,
      );
      expect(neResult.nodesToRender.first.id, 3,
          reason: 'NE node closest to NE-centered viewport');
    });

    test('order is stable for repeated calls with same viewport', () {
      final bounds = LatLngBounds(LatLng(38.0, -78.0), LatLng(39.0, -77.0));
      makeNodes() => [
        nodeAt(1, 38.9, -77.9),
        nodeAt(2, 38.5, -77.5),
        nodeAt(3, 38.1, -77.1),
        nodeAt(4, 38.51, -77.49),
        nodeAt(5, 38.0, -78.0),
      ];

      testNodes = makeNodes();
      final result1 = dataManager.getNodesForRendering(
        currentZoom: 14, mapBounds: bounds,
        uploadMode: UploadMode.production, maxNodes: 3,
      );

      testNodes = makeNodes();
      final result2 = dataManager.getNodesForRendering(
        currentZoom: 14, mapBounds: bounds,
        uploadMode: UploadMode.production, maxNodes: 3,
      );

      expect(
        result1.nodesToRender.map((n) => n.id).toList(),
        result2.nodesToRender.map((n) => n.id).toList(),
      );
    });

    test('filters out invalid coordinates before prioritizing', () {
      final bounds = LatLngBounds(LatLng(38.0, -78.0), LatLng(39.0, -77.0));
      testNodes = [
        nodeAt(1, 0, 0),          // invalid (0,0)
        nodeAt(2, 38.5, -77.5),   // valid, at center
        nodeAt(3, 200, -77.5),    // invalid lat
      ];

      final result = dataManager.getNodesForRendering(
        currentZoom: 14,
        mapBounds: bounds,
        uploadMode: UploadMode.production,
        maxNodes: 10,
      );

      expect(result.nodesToRender.length, 1);
      expect(result.nodesToRender.first.id, 2);
    });
  });
}

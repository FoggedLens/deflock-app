import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:deflockapp/widgets/map/coverage_overlay.dart';
import 'package:deflockapp/services/node_spatial_cache.dart';

void main() {
  CachedArea makeArea(double south, double west, double north, double east,
      {DateTime? fetchedAt}) {
    return CachedArea(
      LatLngBounds(LatLng(south, west), LatLng(north, east)),
      fetchedAt ?? DateTime.now(),
    );
  }

  group('CoverageOverlay.build', () {
    test('returns null when show is false', () {
      final result = CoverageOverlay.build(
        fetchedAreas: [makeArea(38, -78, 39, -77)],
        show: false,
      );
      expect(result, isNull);
    });

    test('returns null when fetchedAreas is empty', () {
      final result = CoverageOverlay.build(fetchedAreas: [], show: true);
      expect(result, isNull);
    });

    test('builds correct fog polygon with holes when enabled', () {
      final areas = [
        makeArea(38, -78, 39, -77),
        makeArea(40, -76, 41, -75),
      ];

      final result = CoverageOverlay.build(fetchedAreas: areas, show: true);
      expect(result, isNotNull);
      expect(result, isA<PolygonLayer>());

      final layer = result!;
      expect(layer.polygons.isNotEmpty, isTrue);

      // First polygon is the fog (world with holes)
      final fog = layer.polygons.first;
      expect(fog.points, hasLength(4)); // world corners
      expect(fog.holePointsList, hasLength(2)); // one hole per fetched area
      expect(fog.holePointsList![0], hasLength(4)); // rectangle = 4 points
      expect(fog.holePointsList![1], hasLength(4));
    });
  });
}

import 'dart:math';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:deflockapp/services/map_data_submodules/tiles_from_local.dart';
import 'package:deflockapp/services/offline_areas/offline_tile_utils.dart';

void main() {
  group('normalizeBounds', () {
    test('swapped corners are normalized', () {
      // NE as first arg, SW as second (swapped)
      final swapped = LatLngBounds(
        const LatLng(52.0, 1.0),   // NE corner passed as SW
        const LatLng(51.0, -1.0),  // SW corner passed as NE
      );
      final normalized = normalizeBounds(swapped);
      expect(normalized.south, closeTo(51.0, 1e-6));
      expect(normalized.north, closeTo(52.0, 1e-6));
      expect(normalized.west, closeTo(-1.0, 1e-6));
      expect(normalized.east, closeTo(1.0, 1e-6));
    });

    test('degenerate (zero-width) bounds are expanded', () {
      final point = LatLngBounds(
        const LatLng(51.5, -0.1),
        const LatLng(51.5, -0.1),
      );
      final normalized = normalizeBounds(point);
      expect(normalized.south, lessThan(51.5));
      expect(normalized.north, greaterThan(51.5));
      expect(normalized.west, lessThan(-0.1));
      expect(normalized.east, greaterThan(-0.1));
    });

    test('already-normalized bounds are unchanged', () {
      final normal = LatLngBounds(
        const LatLng(40.0, -10.0),
        const LatLng(60.0, 30.0),
      );
      final normalized = normalizeBounds(normal);
      expect(normalized.south, closeTo(40.0, 1e-6));
      expect(normalized.north, closeTo(60.0, 1e-6));
      expect(normalized.west, closeTo(-10.0, 1e-6));
      expect(normalized.east, closeTo(30.0, 1e-6));
    });
  });

  group('tileInBounds', () {
    /// Helper: compute expected tile range for [bounds] at [z] using the same
    /// Mercator projection math and return whether (x, y) is within range.
    bool referenceTileInBounds(
        LatLngBounds bounds, int z, int x, int y) {
      final n = pow(2.0, z);
      final minX = ((bounds.west + 180.0) / 360.0 * n).floor();
      final maxX = ((bounds.east + 180.0) / 360.0 * n).floor();
      final minY = ((1.0 -
                  log(tan(bounds.north * pi / 180.0) +
                      1.0 / cos(bounds.north * pi / 180.0)) /
                      pi) /
              2.0 *
              n)
          .floor();
      final maxY = ((1.0 -
                  log(tan(bounds.south * pi / 180.0) +
                      1.0 / cos(bounds.south * pi / 180.0)) /
                      pi) /
              2.0 *
              n)
          .floor();
      return x >= minX && x <= maxX && y >= minY && y <= maxY;
    }

    test('zoom 0: single tile covers the whole world', () {
      final world = LatLngBounds(
        const LatLng(-85, -180),
        const LatLng(85, 180),
      );
      expect(tileInBounds(world, 0, 0, 0), isTrue);
    });

    test('zoom 1: London area covers NW and NE quadrants', () {
      // Bounds straddling the prime meridian in the northern hemisphere
      final londonArea = LatLngBounds(
        const LatLng(51.0, -1.0),
        const LatLng(52.0, 1.0),
      );

      // NW quadrant (x=0, y=0) — should be in bounds
      expect(tileInBounds(londonArea, 1, 0, 0), isTrue);
      // NE quadrant (x=1, y=0) — should be in bounds
      expect(tileInBounds(londonArea, 1, 1, 0), isTrue);
      // SW quadrant (x=0, y=1) — southern hemisphere, out of bounds
      expect(tileInBounds(londonArea, 1, 0, 1), isFalse);
      // SE quadrant (x=1, y=1) — southern hemisphere, out of bounds
      expect(tileInBounds(londonArea, 1, 1, 1), isFalse);
    });

    test('zoom 2: London area covers specific tiles', () {
      final londonArea = LatLngBounds(
        const LatLng(51.0, -1.0),
        const LatLng(52.0, 1.0),
      );

      // Expected: X 1-2, Y 1
      expect(tileInBounds(londonArea, 2, 1, 1), isTrue);
      expect(tileInBounds(londonArea, 2, 2, 1), isTrue);
      // Outside X range
      expect(tileInBounds(londonArea, 2, 0, 1), isFalse);
      expect(tileInBounds(londonArea, 2, 3, 1), isFalse);
      // Outside Y range
      expect(tileInBounds(londonArea, 2, 1, 0), isFalse);
      expect(tileInBounds(londonArea, 2, 1, 2), isFalse);
    });

    test('southern hemisphere: Sydney area', () {
      final sydneyArea = LatLngBounds(
        const LatLng(-34.0, 151.0),
        const LatLng(-33.5, 151.5),
      );

      // At zoom 1, Sydney is in the SE quadrant (x=1, y=1)
      expect(tileInBounds(sydneyArea, 1, 1, 1), isTrue);
      expect(tileInBounds(sydneyArea, 1, 0, 0), isFalse);
      expect(tileInBounds(sydneyArea, 1, 0, 1), isFalse);
      expect(tileInBounds(sydneyArea, 1, 1, 0), isFalse);
    });

    test('western hemisphere: NYC area at zoom 4', () {
      final nycArea = LatLngBounds(
        const LatLng(40.5, -74.5),
        const LatLng(41.0, -73.5),
      );

      // At zoom 4 (16x16), NYC should be around x=4-5, y=6
      // x = floor((-74.5+180)/360 * 16) = floor(105.5/360*16) = floor(4.69) = 4
      // x = floor((-73.5+180)/360 * 16) = floor(106.5/360*16) = floor(4.73) = 4
      // So x range is just 4
      expect(tileInBounds(nycArea, 4, 4, 6), isTrue);
      expect(tileInBounds(nycArea, 4, 5, 6), isFalse);
      expect(tileInBounds(nycArea, 4, 3, 6), isFalse);
    });

    test('higher zoom: smaller area at zoom 10', () {
      // Small area around central London
      final centralLondon = LatLngBounds(
        const LatLng(51.49, -0.13),
        const LatLng(51.52, -0.08),
      );

      // Compute expected tile range at zoom 10 using reference
      const z = 10;
      final n = pow(2.0, z);
      final expectedMinX =
          ((-0.13 + 180.0) / 360.0 * n).floor();
      final expectedMaxX =
          ((-0.08 + 180.0) / 360.0 * n).floor();

      // Tiles inside the computed range should be in bounds
      for (var x = expectedMinX; x <= expectedMaxX; x++) {
        expect(
          referenceTileInBounds(centralLondon, z, x, 340),
          equals(tileInBounds(centralLondon, z, x, 340)),
          reason: 'Mismatch at tile ($x, 340, $z)',
        );
      }

      // Tiles outside X range should not be in bounds
      expect(tileInBounds(centralLondon, z, expectedMinX - 1, 340), isFalse);
      expect(tileInBounds(centralLondon, z, expectedMaxX + 1, 340), isFalse);
    });

    test('tile exactly at boundary is included', () {
      // Bounds whose edges align exactly with tile boundaries at zoom 1
      // At zoom 1: x=0 covers lon -180 to 0, x=1 covers lon 0 to 180
      final halfWorld = LatLngBounds(
        const LatLng(0.0, 0.0),
        const LatLng(60.0, 180.0),
      );

      // Tile (1, 0, 1) should be in bounds (NE quadrant)
      expect(tileInBounds(halfWorld, 1, 1, 0), isTrue);
    });

    test('anti-meridian: bounds crossing 180° longitude', () {
      // Bounds from eastern Russia (170°E) to Alaska (170°W = -170°)
      // After normalization, west=170 east=-170 which is swapped —
      // normalizeBounds will swap to west=-170 east=170, which covers
      // nearly the whole world. This is the expected behavior since
      // LatLngBounds doesn't support anti-meridian wrapping.
      final antiMeridian = normalizeBounds(LatLngBounds(
        const LatLng(50.0, 170.0),
        const LatLng(70.0, -170.0),
      ));

      // After normalization, west=-170 east=170 (covers most longitudes)
      // At zoom 2, tiles 0-3 along X axis
      // Since the normalized bounds cover lon -170 to 170 (340° of 360°),
      // almost all tiles should be in bounds
      expect(tileInBounds(antiMeridian, 2, 0, 0), isTrue);
      expect(tileInBounds(antiMeridian, 2, 1, 0), isTrue);
      expect(tileInBounds(antiMeridian, 2, 2, 0), isTrue);
      expect(tileInBounds(antiMeridian, 2, 3, 0), isTrue);
    });

    test('exhaustive check at zoom 3 matches reference', () {
      final bounds = LatLngBounds(
        const LatLng(40.0, -10.0),
        const LatLng(60.0, 30.0),
      );

      // Check all 64 tiles at zoom 3 against reference implementation
      const z = 3;
      final tilesPerSide = pow(2, z).toInt();
      for (var x = 0; x < tilesPerSide; x++) {
        for (var y = 0; y < tilesPerSide; y++) {
          expect(
            tileInBounds(bounds, z, x, y),
            equals(referenceTileInBounds(bounds, z, x, y)),
            reason: 'Mismatch at tile ($x, $y, $z)',
          );
        }
      }
    });
  });
}

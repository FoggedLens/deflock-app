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
    /// Reference implementation that matches computeTileList's ±1 tile padding
    /// and clamping to [0, nTiles-1].
    bool referenceTileInBounds(
        LatLngBounds bounds, int z, int x, int y) {
      final int nTiles = 1 << z;
      final double n = nTiles.toDouble();
      int minX = ((bounds.west + 180.0) / 360.0 * n).floor();
      int maxX = ((bounds.east + 180.0) / 360.0 * n).floor();
      int minY = ((1.0 -
                  log(tan(bounds.north * pi / 180.0) +
                      1.0 / cos(bounds.north * pi / 180.0)) /
                      pi) /
              2.0 *
              n)
          .floor();
      int maxY = ((1.0 -
                  log(tan(bounds.south * pi / 180.0) +
                      1.0 / cos(bounds.south * pi / 180.0)) /
                      pi) /
              2.0 *
              n)
          .floor();
      // Match computeTileList: ±1 padding with clamping
      minX = max(0, minX - 1);
      maxX = min(nTiles - 1, maxX + 1);
      minY = max(0, minY - 1);
      maxY = min(nTiles - 1, maxY + 1);
      return x >= minX && x <= maxX && y >= minY && y <= maxY;
    }

    test('zoom 0: single tile covers the whole world', () {
      final world = LatLngBounds(
        const LatLng(-85, -180),
        const LatLng(85, 180),
      );
      expect(tileInBounds(world, 0, 0, 0), isTrue);
    });

    test('zoom 1: London area covers NW and NE quadrants (with padding)', () {
      // Bounds straddling the prime meridian in the northern hemisphere
      final londonArea = LatLngBounds(
        const LatLng(51.0, -1.0),
        const LatLng(52.0, 1.0),
      );

      // At zoom 1 (2x2 grid), London is in NW (0,0) and NE (1,0).
      // With ±1 padding clamped to [0,1], all 4 tiles are included.
      expect(tileInBounds(londonArea, 1, 0, 0), isTrue);
      expect(tileInBounds(londonArea, 1, 1, 0), isTrue);
      expect(tileInBounds(londonArea, 1, 0, 1), isTrue);  // padding
      expect(tileInBounds(londonArea, 1, 1, 1), isTrue);  // padding
    });

    test('zoom 2: London area covers tiles with padding', () {
      final londonArea = LatLngBounds(
        const LatLng(51.0, -1.0),
        const LatLng(52.0, 1.0),
      );

      // Core: X 1-2, Y 1. With ±1 padding: X 0-3, Y 0-2
      expect(tileInBounds(londonArea, 2, 1, 1), isTrue);
      expect(tileInBounds(londonArea, 2, 2, 1), isTrue);
      // Padding tiles
      expect(tileInBounds(londonArea, 2, 0, 1), isTrue);  // X-1 padding
      expect(tileInBounds(londonArea, 2, 3, 1), isTrue);  // X+1 padding
      expect(tileInBounds(londonArea, 2, 1, 0), isTrue);  // Y-1 padding
      expect(tileInBounds(londonArea, 2, 1, 2), isTrue);  // Y+1 padding
    });

    test('southern hemisphere: Sydney area', () {
      final sydneyArea = LatLngBounds(
        const LatLng(-34.0, 151.0),
        const LatLng(-33.5, 151.5),
      );

      // At zoom 1, Sydney is in the SE quadrant (x=1, y=1).
      // With ±1 padding clamped to [0,1], all tiles are in range.
      expect(tileInBounds(sydneyArea, 1, 1, 1), isTrue);
      expect(tileInBounds(sydneyArea, 1, 0, 0), isTrue);  // padding
      expect(tileInBounds(sydneyArea, 1, 0, 1), isTrue);  // padding
      expect(tileInBounds(sydneyArea, 1, 1, 0), isTrue);  // padding
    });

    test('western hemisphere: NYC area at zoom 4', () {
      final nycArea = LatLngBounds(
        const LatLng(40.5, -74.5),
        const LatLng(41.0, -73.5),
      );

      // Core tile: x=4, y=6. With ±1 padding: x=3-5, y=5-7
      expect(tileInBounds(nycArea, 4, 4, 6), isTrue);
      expect(tileInBounds(nycArea, 4, 5, 6), isTrue);  // X+1 padding
      expect(tileInBounds(nycArea, 4, 3, 6), isTrue);  // X-1 padding
      // Well outside even padding range
      expect(tileInBounds(nycArea, 4, 1, 6), isFalse);
      expect(tileInBounds(nycArea, 4, 7, 6), isFalse);
    });

    test('higher zoom: smaller area at zoom 10', () {
      // Small area around central London
      final centralLondon = LatLngBounds(
        const LatLng(51.49, -0.13),
        const LatLng(51.52, -0.08),
      );

      // Compute expected tile range at zoom 10 using reference (with padding)
      const z = 10;
      final int nTiles = 1 << z;
      final double n = nTiles.toDouble();
      final coreMinX = ((-0.13 + 180.0) / 360.0 * n).floor();
      final coreMaxX = ((-0.08 + 180.0) / 360.0 * n).floor();
      final paddedMinX = max(0, coreMinX - 1);
      final paddedMaxX = min(nTiles - 1, coreMaxX + 1);

      // Tiles inside the padded range should be in bounds
      for (var x = paddedMinX; x <= paddedMaxX; x++) {
        expect(
          tileInBounds(centralLondon, z, x, 340),
          isTrue,
          reason: 'Tile ($x, 340, $z) should be in padded range',
        );
      }

      // Tiles outside padded range should not be in bounds
      expect(tileInBounds(centralLondon, z, paddedMinX - 1, 340), isFalse);
      expect(tileInBounds(centralLondon, z, paddedMaxX + 1, 340), isFalse);
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

    test('tileInBounds matches computeTileList for representative bounds', () {
      // Verify that tileInBounds returns true for exactly the tiles
      // that computeTileList would generate at a given zoom.
      final bounds = LatLngBounds(
        const LatLng(51.0, -1.0),
        const LatLng(52.0, 1.0),
      );
      const z = 5;
      final tileSet = computeTileList(bounds, z, z);
      final nTiles = pow(2, z).toInt();

      for (var x = 0; x < nTiles; x++) {
        for (var y = 0; y < nTiles; y++) {
          final inComputeList = tileSet.any(
            (t) => t[0] == z && t[1] == x && t[2] == y,
          );
          expect(
            tileInBounds(bounds, z, x, y),
            equals(inComputeList),
            reason: 'Mismatch at tile ($x, $y, $z): '
                'tileInBounds=${tileInBounds(bounds, z, x, y)}, '
                'inComputeList=$inComputeList',
          );
        }
      }
    });
  });
}

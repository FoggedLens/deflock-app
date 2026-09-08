import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:deflockapp/services/geo_bounds.dart';

/// Real-world distance from a bounds edge back to its center, so the box can be
/// checked in meters rather than in degrees.
double _metersBetween(LatLng a, LatLng b) => Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );

void main() {
  group('boundsAround', () {
    test('contains the center', () {
      const center = LatLng(38.9, -77.0);
      final bounds = boundsAround(center, 200);
      expect(bounds.contains(center), isTrue);
    });

    test('reaches at least the requested radius north/south and east/west', () {
      const center = LatLng(38.9, -77.0);
      const radius = 500;
      final bounds = boundsAround(center, radius);

      final north = _metersBetween(center, LatLng(bounds.north, center.longitude));
      final south = _metersBetween(center, LatLng(bounds.south, center.longitude));
      final east = _metersBetween(center, LatLng(center.latitude, bounds.east));
      final west = _metersBetween(center, LatLng(center.latitude, bounds.west));

      for (final reach in [north, south, east, west]) {
        // At least the radius, and not wildly oversized (the box is a square,
        // so its corners legitimately overshoot, but its edges should not).
        expect(reach, greaterThanOrEqualTo(radius * 0.98));
        expect(reach, lessThan(radius * 1.2));
      }
    });

    test('widens longitude at high latitude to keep the real radius', () {
      const radius = 1000;
      final equator = boundsAround(const LatLng(0, 0), radius);
      final far = boundsAround(const LatLng(64.0, 0), radius);

      final equatorLngSpan = equator.east - equator.west;
      final farLngSpan = far.east - far.west;

      // cos(64°) ≈ 0.438, so the degree span must be roughly 2.3x wider.
      expect(farLngSpan, greaterThan(equatorLngSpan * 2));

      // ...and that wider span should still be ~1000m on the ground.
      final reach = _metersBetween(
        const LatLng(64.0, 0),
        LatLng(64.0, far.east),
      );
      expect(reach, greaterThanOrEqualTo(radius * 0.98));
      expect(reach, lessThan(radius * 1.2));
    });

    test('does not blow past the poles or the antimeridian', () {
      for (final center in [
        const LatLng(89.99, 179.99),
        const LatLng(-89.99, -179.99),
      ]) {
        final bounds = boundsAround(center, 100000);
        expect(bounds.north, lessThanOrEqualTo(90.0));
        expect(bounds.south, greaterThanOrEqualTo(-90.0));
        expect(bounds.east, lessThanOrEqualTo(180.0));
        expect(bounds.west, greaterThanOrEqualTo(-180.0));
      }
    });

    test('a zero radius still yields usable bounds containing the center', () {
      const center = LatLng(38.9, -77.0);
      final bounds = boundsAround(center, 0);
      expect(bounds.contains(center), isTrue);
    });

    test('grows with the alert distance', () {
      const center = LatLng(38.9, -77.0);
      final near = boundsAround(center, 100);
      final far = boundsAround(center, 1600);
      expect(far.north - far.south, greaterThan(near.north - near.south));
    });
  });
}

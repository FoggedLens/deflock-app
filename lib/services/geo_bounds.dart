import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

/// Mean meters per degree of latitude. Constant enough at any latitude for
/// picking a node lookup box.
const double _metersPerDegreeLat = 111320.0;

/// Smallest cos(latitude) we will divide by. Past ~89.4° the true factor tends
/// to zero and the longitude span would blow up to the whole globe.
const double _minCosLatitude = 0.01;

/// A square of roughly [radiusMeters] in every direction around [center].
///
/// Used to pull cached nodes near a GPS position, as opposed to near whatever
/// the map camera is showing — the camera is frozen while the app is
/// backgrounded, so it is not a usable proxy for where the user is.
///
/// A degree of longitude shrinks by cos(latitude), so the box is widened east
/// to west to keep the real-world radius honest as you move away from the
/// equator.
LatLngBounds boundsAround(LatLng center, num radiusMeters) {
  final radius = radiusMeters.toDouble().abs();
  final latDelta = radius / _metersPerDegreeLat;
  final cosLat = math.cos(center.latitude * math.pi / 180).abs();
  final lngDelta =
      radius / (_metersPerDegreeLat * math.max(cosLat, _minCosLatitude));

  return LatLngBounds(
    LatLng(
      (center.latitude - latDelta).clamp(-90.0, 90.0),
      (center.longitude - lngDelta).clamp(-180.0, 180.0),
    ),
    LatLng(
      (center.latitude + latDelta).clamp(-90.0, 90.0),
      (center.longitude + lngDelta).clamp(-180.0, 180.0),
    ),
  );
}

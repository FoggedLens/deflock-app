import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../services/node_spatial_cache.dart';

/// Builds a "fog of war" polygon layer showing which map areas have
/// surveillance data loaded. Unfetched areas are dimmed; fetched areas
/// are clear (with optional debug tinting).
///
/// Uses a world-spanning polygon with holes punched for each cached area.
class CoverageOverlay {
  CoverageOverlay._();

  static const _freshAge = Duration(minutes: 10);
  static const _staleAge = Duration(hours: 1);

  /// Build the coverage overlay layer. Returns null when the overlay is
  /// disabled or there are no fetched areas to visualize.
  static PolygonLayer? build({
    required List<CachedArea> fetchedAreas,
    required bool show,
  }) {
    if (!show || fetchedAreas.isEmpty) return null;

    // World-spanning polygon (the "fog")
    const worldPoints = [
      LatLng(-85, -180),
      LatLng(-85, 180),
      LatLng(85, 180),
      LatLng(85, -180),
    ];

    // Convert each fetched area bounds into a hole (clockwise winding)
    final holes = fetchedAreas
        .map((a) => _boundsToCorners(a.bounds))
        .toList();

    // Debug mode: visible orange fog + age-colored fetched areas
    // Production: very subtle grey fog, no border
    final fogColor = kEnableDevelopmentModes
        ? const Color(0x30FF6D00) // orange, ~19% opacity
        : const Color(0x18000000); // black, ~9% opacity

    final polygons = <Polygon>[
      Polygon(
        points: worldPoints,
        holePointsList: holes,
        color: fogColor,
        borderStrokeWidth: 0,
      ),
    ];

    // In debug mode, draw age-colored borders around each fetched area
    if (kEnableDevelopmentModes) {
      final now = DateTime.now();
      for (final area in fetchedAreas) {
        final age = now.difference(area.fetchedAt);
        final Color fillColor;
        final Color borderColor;
        if (age < _freshAge) {
          fillColor = const Color(0x1800C853);  // green ~9%
          borderColor = const Color(0x6000C853); // green ~38%
        } else if (age < _staleAge) {
          fillColor = const Color(0x18FFD600);   // yellow ~9%
          borderColor = const Color(0x60FFD600);  // yellow ~38%
        } else {
          fillColor = const Color(0x18FF6D00);   // orange ~9%
          borderColor = const Color(0x60FF6D00);  // orange ~38%
        }

        polygons.add(Polygon(
          points: _boundsToCorners(area.bounds),
          color: fillColor,
          borderColor: borderColor,
          borderStrokeWidth: 1.5,
        ));
      }
    }

    return PolygonLayer(polygons: polygons);
  }

  static List<LatLng> _boundsToCorners(LatLngBounds b) => [
    LatLng(b.south, b.west),
    LatLng(b.north, b.west),
    LatLng(b.north, b.east),
    LatLng(b.south, b.east),
  ];
}

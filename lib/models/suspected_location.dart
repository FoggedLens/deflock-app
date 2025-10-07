import 'dart:convert';
import 'package:latlong2/latlong.dart';

/// A suspected surveillance location from the CSV data
class SuspectedLocation {
  final String ticketNo;
  final String? urlFull;
  final String? addr;
  final String? street;
  final String? city;
  final String? state;
  final String? digSiteIntersectingStreet;
  final String? digWorkDoneFor;
  final String? digSiteRemarks;
  final Map<String, dynamic>? geoJson;
  final LatLng centroid;
  final List<LatLng> bounds;

  SuspectedLocation({
    required this.ticketNo,
    this.urlFull,
    this.addr,
    this.street,
    this.city,
    this.state,
    this.digSiteIntersectingStreet,
    this.digWorkDoneFor,
    this.digSiteRemarks,
    this.geoJson,
    required this.centroid,
    required this.bounds,
  });

  /// Create from CSV row data
  factory SuspectedLocation.fromCsvRow(Map<String, dynamic> row) {
    final locationString = row['location'] as String?;
    LatLng centroid = const LatLng(0, 0);
    List<LatLng> bounds = [];
    Map<String, dynamic>? geoJson;

    // Parse GeoJSON if available
    if (locationString != null && locationString.isNotEmpty) {
      try {
        geoJson = jsonDecode(locationString) as Map<String, dynamic>;
        final coordinates = _extractCoordinatesFromGeoJson(geoJson);
        centroid = coordinates.centroid;
        bounds = coordinates.bounds;
      } catch (e) {
        // If GeoJSON parsing fails, use default coordinates
        print('[SuspectedLocation] Failed to parse GeoJSON for ticket ${row['ticket_no']}: $e');
        print('[SuspectedLocation] Location string: $locationString');
      }
    }

    return SuspectedLocation(
      ticketNo: row['ticket_no']?.toString() ?? '',
      urlFull: row['url_full']?.toString(),
      addr: row['addr']?.toString(),
      street: row['street']?.toString(),
      city: row['city']?.toString(),
      state: row['state']?.toString(),
      digSiteIntersectingStreet: row['dig_site_intersecting_street']?.toString(),
      digWorkDoneFor: row['dig_work_done_for']?.toString(),
      digSiteRemarks: row['dig_site_remarks']?.toString(),
      geoJson: geoJson,
      centroid: centroid,
      bounds: bounds,
    );
  }

  /// Extract coordinates from GeoJSON
  static ({LatLng centroid, List<LatLng> bounds}) _extractCoordinatesFromGeoJson(Map<String, dynamic> geoJson) {
    try {
      // The geoJson IS the geometry object (not wrapped in a 'geometry' property)
      final coordinates = geoJson['coordinates'] as List?;
      if (coordinates == null || coordinates.isEmpty) {
        print('[SuspectedLocation] No coordinates found in GeoJSON');
        return (centroid: const LatLng(0, 0), bounds: <LatLng>[]);
      }

      final List<LatLng> points = [];
      
      // Handle different geometry types
      final type = geoJson['type'] as String?;
      switch (type) {
        case 'Point':
          if (coordinates.length >= 2) {
            final point = LatLng(
              (coordinates[1] as num).toDouble(),
              (coordinates[0] as num).toDouble(),
            );
            points.add(point);
          }
          break;
        case 'Polygon':
          // Polygon coordinates are [[[lng, lat], ...]]
          if (coordinates.isNotEmpty) {
            final ring = coordinates[0] as List;
            for (final coord in ring) {
              if (coord is List && coord.length >= 2) {
                points.add(LatLng(
                  (coord[1] as num).toDouble(),
                  (coord[0] as num).toDouble(),
                ));
              }
            }
          }
          break;
        case 'MultiPolygon':
          // MultiPolygon coordinates are [[[[lng, lat], ...], ...], ...]
          for (final polygon in coordinates) {
            if (polygon is List && polygon.isNotEmpty) {
              final ring = polygon[0] as List;
              for (final coord in ring) {
                if (coord is List && coord.length >= 2) {
                  points.add(LatLng(
                    (coord[1] as num).toDouble(),
                    (coord[0] as num).toDouble(),
                  ));
                }
              }
            }
          }
          break;
        default:
          print('Unsupported geometry type: $type');
      }

      if (points.isEmpty) {
        return (centroid: const LatLng(0, 0), bounds: <LatLng>[]);
      }

      // Calculate centroid
      double sumLat = 0;
      double sumLng = 0;
      for (final point in points) {
        sumLat += point.latitude;
        sumLng += point.longitude;
      }
      final centroid = LatLng(sumLat / points.length, sumLng / points.length);

      return (centroid: centroid, bounds: points);
    } catch (e) {
      print('Error extracting coordinates from GeoJSON: $e');
      return (centroid: const LatLng(0, 0), bounds: <LatLng>[]);
    }
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() => {
    'ticket_no': ticketNo,
    'url_full': urlFull,
    'addr': addr,
    'street': street,
    'city': city,
    'state': state,
    'dig_site_intersecting_street': digSiteIntersectingStreet,
    'dig_work_done_for': digWorkDoneFor,
    'dig_site_remarks': digSiteRemarks,
    'geo_json': geoJson,
    'centroid_lat': centroid.latitude,
    'centroid_lng': centroid.longitude,
    'bounds': bounds.map((p) => [p.latitude, p.longitude]).toList(),
  };

  /// Create from stored JSON
  factory SuspectedLocation.fromJson(Map<String, dynamic> json) {
    final boundsData = json['bounds'] as List?;
    final bounds = boundsData?.map((b) => LatLng(
      (b[0] as num).toDouble(),
      (b[1] as num).toDouble(),
    )).toList() ?? <LatLng>[];

    return SuspectedLocation(
      ticketNo: json['ticket_no'] ?? '',
      urlFull: json['url_full'],
      addr: json['addr'],
      street: json['street'],
      city: json['city'],
      state: json['state'],
      digSiteIntersectingStreet: json['dig_site_intersecting_street'],
      digWorkDoneFor: json['dig_work_done_for'],
      digSiteRemarks: json['dig_site_remarks'],
      geoJson: json['geo_json'],
      centroid: LatLng(
        (json['centroid_lat'] as num).toDouble(),
        (json['centroid_lng'] as num).toDouble(),
      ),
      bounds: bounds,
    );
  }

  /// Get a formatted display address
  String get displayAddress {
    final parts = <String>[];
    if (addr?.isNotEmpty == true) parts.add(addr!);
    if (street?.isNotEmpty == true) parts.add(street!);
    if (city?.isNotEmpty == true) parts.add(city!);
    if (state?.isNotEmpty == true) parts.add(state!);
    return parts.isNotEmpty ? parts.join(', ') : 'No address available';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuspectedLocation &&
          runtimeType == other.runtimeType &&
          ticketNo == other.ticketNo;

  @override
  int get hashCode => ticketNo.hashCode;
}
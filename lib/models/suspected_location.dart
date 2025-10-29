import 'dart:convert';
import 'package:latlong2/latlong.dart';

/// A suspected surveillance location from the CSV data
class SuspectedLocation {
  final String ticketNo;
  final LatLng centroid;
  final List<LatLng> bounds;
  final Map<String, dynamic>? geoJson;
  final Map<String, dynamic> allFields; // All CSV fields except location and ticket_no

  SuspectedLocation({
    required this.ticketNo,
    required this.centroid,
    required this.bounds,
    this.geoJson,
    required this.allFields,
  });

  /// Create from CSV row data
  factory SuspectedLocation.fromCsvRow(Map<String, dynamic> row) {
    final locationString = row['location'] as String?;
    final ticketNo = row['ticket_no']?.toString() ?? '';
    
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
        print('[SuspectedLocation] Failed to parse GeoJSON for ticket $ticketNo: $e');
        print('[SuspectedLocation] Location string: $locationString');
      }
    }

    // Store all fields except location and ticket_no
    final allFields = Map<String, dynamic>.from(row);
    allFields.remove('location');
    allFields.remove('ticket_no');

    return SuspectedLocation(
      ticketNo: ticketNo,
      centroid: centroid,
      bounds: bounds,
      geoJson: geoJson,
      allFields: allFields,
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
    'geo_json': geoJson,
    'centroid_lat': centroid.latitude,
    'centroid_lng': centroid.longitude,
    'bounds': bounds.map((p) => [p.latitude, p.longitude]).toList(),
    'all_fields': allFields,
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
      geoJson: json['geo_json'],
      centroid: LatLng(
        (json['centroid_lat'] as num).toDouble(),
        (json['centroid_lng'] as num).toDouble(),
      ),
      bounds: bounds,
      allFields: Map<String, dynamic>.from(json['all_fields'] ?? {}),
    );
  }

  /// Get a formatted display address
  String get displayAddress {
    final parts = <String>[];
    final addr = allFields['addr']?.toString();
    final street = allFields['street']?.toString();
    final city = allFields['city']?.toString();
    final state = allFields['state']?.toString();
    
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
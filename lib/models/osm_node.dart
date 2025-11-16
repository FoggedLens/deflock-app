import 'package:latlong2/latlong.dart';

class OsmNode {
  final int id;
  final LatLng coord;
  final Map<String, String> tags;
  final bool isConstrained; // true if part of any way/relation

  OsmNode({
    required this.id,
    required this.coord,
    required this.tags,
    this.isConstrained = false, // Default to unconstrained for backward compatibility
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': coord.latitude,
    'lon': coord.longitude,
    'tags': tags,
    'isConstrained': isConstrained,
  };

  factory OsmNode.fromJson(Map<String, dynamic> json) {
    final tags = <String, String>{};
    if (json['tags'] != null) {
      (json['tags'] as Map<String, dynamic>).forEach((k, v) {
        tags[k.toString()] = v.toString();
      });
    }
    return OsmNode(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id'].toString()) ?? 0,
      coord: LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
      tags: tags,
      isConstrained: json['isConstrained'] as bool? ?? false, // Default to false for backward compatibility
    );
  }

  bool get hasDirection => directionDeg.isNotEmpty;

  List<double> get directionDeg {
    final raw = tags['direction'] ?? tags['camera:direction'];
    if (raw == null) return [];

    // Compass direction to degree mapping
    const compassDirections = {
      'N': 0.0, 'NNE': 22.5, 'NE': 45.0, 'ENE': 67.5,
      'E': 90.0, 'ESE': 112.5, 'SE': 135.0, 'SSE': 157.5,
      'S': 180.0, 'SSW': 202.5, 'SW': 225.0, 'WSW': 247.5,
      'W': 270.0, 'WNW': 292.5, 'NW': 315.0, 'NNW': 337.5,
    };

    // Split on semicolons and parse each direction
    final directions = <double>[];
    final parts = raw.split(';');
    
    for (final part in parts) {
      final trimmed = part.trim().toUpperCase();
      if (trimmed.isEmpty) continue;
      
      // First try compass direction lookup
      if (compassDirections.containsKey(trimmed)) {
        directions.add(compassDirections[trimmed]!);
        continue;
      }
      
      // Then try numeric parsing
      final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(trimmed);
      if (match == null) continue;

      final numStr = match.group(0);
      final val = double.tryParse(numStr ?? '');
      if (val == null) continue;

      // Normalize: wrap negative or >360 into 0‑359 range
      final normalized = ((val % 360) + 360) % 360;
      directions.add(normalized);
    }
    
    return directions;
  }
}
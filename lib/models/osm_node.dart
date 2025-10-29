import 'package:latlong2/latlong.dart';

class OsmNode {
  final int id;
  final LatLng coord;
  final Map<String, String> tags;

  OsmNode({
    required this.id,
    required this.coord,
    required this.tags,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': coord.latitude,
    'lon': coord.longitude,
    'tags': tags,
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
    );
  }

  bool get hasDirection => directionDeg.isNotEmpty;

  List<double> get directionDeg {
    final raw = tags['direction'] ?? tags['camera:direction'];
    if (raw == null) return [];

    // Split on semicolons and parse each direction
    final directions = <double>[];
    final parts = raw.split(';');
    
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      
      // Keep digits, optional dot, optional leading sign
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
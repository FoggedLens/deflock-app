import 'package:latlong2/latlong.dart';

class OsmCameraNode {
  final int id;
  final LatLng coord;
  final Map<String, String> tags;

  OsmCameraNode({
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

  factory OsmCameraNode.fromJson(Map<String, dynamic> json) {
    final tags = <String, String>{};
    if (json['tags'] != null) {
      (json['tags'] as Map<String, dynamic>).forEach((k, v) {
        tags[k.toString()] = v.toString();
      });
    }
    return OsmCameraNode(
      id: json['id'] is int ? json['id'] as int : int.tryParse(json['id'].toString()) ?? 0,
      coord: LatLng((json['lat'] as num).toDouble(), (json['lon'] as num).toDouble()),
      tags: tags,
    );
  }

  bool get hasDirection =>
      tags.containsKey('direction') || tags.containsKey('camera:direction');

  double? get directionDeg {
    final raw = tags['direction'] ?? tags['camera:direction'];
    if (raw == null) return null;

    // Keep digits, optional dot, optional leading sign.
    final match = RegExp(r'[-+]?\d*\.?\d+').firstMatch(raw);
    if (match == null) return null;

    final numStr = match.group(0);
    final val = double.tryParse(numStr ?? '');
    if (val == null) return null;

    // Normalize: wrap negative or >360 into 0‑359 range.
    final normalized = ((val % 360) + 360) % 360;
    return normalized;
  }
}


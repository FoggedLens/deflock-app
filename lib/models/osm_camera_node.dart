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


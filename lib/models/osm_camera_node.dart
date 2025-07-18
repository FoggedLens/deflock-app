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

  bool get hasDirection => tags.containsKey('direction');
  double? get directionDeg =>
      hasDirection ? double.tryParse(tags['direction']!) : null;
}


import 'package:latlong2/latlong.dart';
import 'camera_profile.dart';

class PendingUpload {
  final LatLng coord;
  final double direction;
  final CameraProfile profile;
  int attempts;

  PendingUpload({
    required this.coord,
    required this.direction,
    required this.profile,
    this.attempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'lat': coord.latitude,
        'lon': coord.longitude,
        'dir': direction,
        'profile': profile.name,
        'attempts': attempts,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        coord: LatLng(j['lat'], j['lon']),
        direction: j['dir'],
        profile: CameraProfile.alpr(), // only built‑in for now
        attempts: j['attempts'] ?? 0,
      );
}


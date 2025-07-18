import 'package:latlong2/latlong.dart';
import 'camera_profile.dart';

class PendingUpload {
  final LatLng coord;
  final double direction;
  final CameraProfile profile;
  final DateTime queuedAt;

  PendingUpload({
    required this.coord,
    required this.direction,
    required this.profile,
  }) : queuedAt = DateTime.now();
}


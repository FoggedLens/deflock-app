import 'package:latlong2/latlong.dart';
import 'camera_profile.dart';
import '../state/settings_state.dart';

class PendingUpload {
  final LatLng coord;
  final double direction;
  final CameraProfile profile;
  final UploadMode uploadMode; // Capture upload destination when queued
  final int? originalNodeId; // If this is an edit, the ID of the original OSM node
  int attempts;
  bool error;
  bool completing; // True when upload succeeded but item is showing checkmark briefly

  PendingUpload({
    required this.coord,
    required this.direction,
    required this.profile,
    required this.uploadMode,
    this.originalNodeId,
    this.attempts = 0,
    this.error = false,
    this.completing = false,
  });

  // True if this is an edit of an existing camera, false if it's a new camera
  bool get isEdit => originalNodeId != null;

  // Get display name for the upload destination
  String get uploadModeDisplayName {
    switch (uploadMode) {
      case UploadMode.production:
        return 'Production';
      case UploadMode.sandbox:
        return 'Sandbox';
      case UploadMode.simulate:
        return 'Simulate';
    }
  }

  Map<String, dynamic> toJson() => {
        'lat': coord.latitude,
        'lon': coord.longitude,
        'dir': direction,
        'profile': profile.toJson(),
        'uploadMode': uploadMode.index,
        'originalNodeId': originalNodeId,
        'attempts': attempts,
        'error': error,
        'completing': completing,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        coord: LatLng(j['lat'], j['lon']),
        direction: j['dir'],
        profile: j['profile'] is Map<String, dynamic>
            ? CameraProfile.fromJson(j['profile'])
            : CameraProfile.genericAlpr(),
        uploadMode: j['uploadMode'] != null 
            ? UploadMode.values[j['uploadMode']] 
            : UploadMode.production, // Default for legacy entries
        originalNodeId: j['originalNodeId'],
        attempts: j['attempts'] ?? 0,
        error: j['error'] ?? false,
        completing: j['completing'] ?? false, // Default to false for legacy entries
      );
}


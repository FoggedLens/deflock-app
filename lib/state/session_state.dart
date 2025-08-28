import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/camera_profile.dart';

// ------------------ AddCameraSession ------------------
class AddCameraSession {
  AddCameraSession({required this.profile, this.directionDegrees = 0});
  CameraProfile profile;
  double directionDegrees;
  LatLng? target;
}

class SessionState extends ChangeNotifier {
  AddCameraSession? _session;

  // Getter
  AddCameraSession? get session => _session;

  void startAddSession(List<CameraProfile> enabledProfiles) {
    final submittableProfiles = enabledProfiles.where((p) => p.isSubmittable).toList();
    final defaultProfile = submittableProfiles.isNotEmpty 
        ? submittableProfiles.first 
        : enabledProfiles.first; // Fallback to any enabled profile
    _session = AddCameraSession(profile: defaultProfile);
    notifyListeners();
  }

  void updateSession({
    double? directionDeg,
    CameraProfile? profile,
    LatLng? target,
  }) {
    if (_session == null) return;

    bool dirty = false;
    if (directionDeg != null && directionDeg != _session!.directionDegrees) {
      _session!.directionDegrees = directionDeg;
      dirty = true;
    }
    if (profile != null && profile != _session!.profile) {
      _session!.profile = profile;
      dirty = true;
    }
    if (target != null) {
      _session!.target = target;
      dirty = true;
    }
    if (dirty) notifyListeners();
  }

  void cancelSession() {
    _session = null;
    notifyListeners();
  }

  AddCameraSession? commitSession() {
    if (_session?.target == null) return null;
    
    final session = _session!;
    _session = null;
    notifyListeners();
    return session;
  }
}
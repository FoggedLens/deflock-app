import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'models/camera_profile.dart';
import 'models/pending_upload.dart';

class AddCameraSession {
  AddCameraSession({required this.profile, this.directionDegrees = 0});

  CameraProfile profile;
  double directionDegrees;
  LatLng? target;
}

class AppState extends ChangeNotifier {
  AppState() {
    _profiles = [CameraProfile.alpr()];
    _enabled = {..._profiles}; // all enabled by default
  }

  // ---------- Auth ----------
  bool _loggedIn = false;
  bool get isLoggedIn => _loggedIn;
  void setLoggedIn(bool v) {
    _loggedIn = v;
    notifyListeners();
  }

  // ---------- Profiles & toggles ----------
  late final List<CameraProfile> _profiles;
  late final Set<CameraProfile> _enabled;
  List<CameraProfile> get profiles => List.unmodifiable(_profiles);
  bool isEnabled(CameraProfile p) => _enabled.contains(p);

  void toggleProfile(CameraProfile p, bool enable) {
    enable ? _enabled.add(p) : _enabled.remove(p);
    notifyListeners();
  }

  List<CameraProfile> get enabledProfiles => _profiles
      .where((p) => _enabled.contains(p))
      .toList(growable: false);

  // ---------- Add-camera session ----------
  AddCameraSession? _session;
  AddCameraSession? get session => _session;

  void startAddSession() {
    _session = AddCameraSession(profile: enabledProfiles.first);
    notifyListeners();
  }

  void updateSession({
    double? directionDeg,
    CameraProfile? profile,
    LatLng? target,
  }) {
    if (_session == null) return;
    if (directionDeg != null) _session!.directionDegrees = directionDeg;
    if (profile != null) _session!.profile = profile;
    if (target != null) _session!.target = target;
    notifyListeners();
  }

  void cancelSession() {
    _session = null;
    notifyListeners();
  }

  // ---------- Pending uploads ----------
  final List<PendingUpload> _queue = [];
  List<PendingUpload> get queue => List.unmodifiable(_queue);

  void commitSession() {
    if (_session?.target == null) return;
    _queue.add(
      PendingUpload(
        coord: _session!.target!,
        direction: _session!.directionDegrees,
        profile: _session!.profile,
      ),
    );
    _session = null;
    notifyListeners();
  }
}


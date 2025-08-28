import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/camera_profile.dart';
import '../models/osm_camera_node.dart';

// ------------------ AddCameraSession ------------------
class AddCameraSession {
  AddCameraSession({required this.profile, this.directionDegrees = 0});
  CameraProfile profile;
  double directionDegrees;
  LatLng? target;
}

// ------------------ EditCameraSession ------------------
class EditCameraSession {
  EditCameraSession({
    required this.originalNode,
    required this.profile,
    required this.directionDegrees,
    required this.target,
  });
  
  final OsmCameraNode originalNode; // The original camera being edited
  CameraProfile profile;
  double directionDegrees;
  LatLng target; // Current position (can be dragged)
}

class SessionState extends ChangeNotifier {
  AddCameraSession? _session;
  EditCameraSession? _editSession;

  // Getters
  AddCameraSession? get session => _session;
  EditCameraSession? get editSession => _editSession;

  void startAddSession(List<CameraProfile> enabledProfiles) {
    final submittableProfiles = enabledProfiles.where((p) => p.isSubmittable).toList();
    final defaultProfile = submittableProfiles.isNotEmpty 
        ? submittableProfiles.first 
        : enabledProfiles.first; // Fallback to any enabled profile
    _session = AddCameraSession(profile: defaultProfile);
    _editSession = null; // Clear any edit session
    notifyListeners();
  }

  void startEditSession(OsmCameraNode node, List<CameraProfile> enabledProfiles) {
    final submittableProfiles = enabledProfiles.where((p) => p.isSubmittable).toList();
    
    // Try to find a matching profile based on the node's tags
    CameraProfile matchingProfile = submittableProfiles.isNotEmpty 
        ? submittableProfiles.first 
        : enabledProfiles.first;
    
    // Attempt to find a better match by comparing tags
    for (final profile in submittableProfiles) {
      if (_profileMatchesTags(profile, node.tags)) {
        matchingProfile = profile;
        break;
      }
    }
    
    _editSession = EditCameraSession(
      originalNode: node,
      profile: matchingProfile,
      directionDegrees: node.directionDeg ?? 0,
      target: node.coord,
    );
    _session = null; // Clear any add session
    notifyListeners();
  }

  bool _profileMatchesTags(CameraProfile profile, Map<String, String> tags) {
    // Simple matching: check if all profile tags are present in node tags
    for (final entry in profile.tags.entries) {
      if (tags[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
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

  void updateEditSession({
    double? directionDeg,
    CameraProfile? profile,
    LatLng? target,
  }) {
    if (_editSession == null) return;

    bool dirty = false;
    if (directionDeg != null && directionDeg != _editSession!.directionDegrees) {
      _editSession!.directionDegrees = directionDeg;
      dirty = true;
    }
    if (profile != null && profile != _editSession!.profile) {
      _editSession!.profile = profile;
      dirty = true;
    }
    if (target != null && target != _editSession!.target) {
      _editSession!.target = target;
      dirty = true;
    }
    if (dirty) notifyListeners();
  }

  void cancelSession() {
    _session = null;
    notifyListeners();
  }

  void cancelEditSession() {
    _editSession = null;
    notifyListeners();
  }

  AddCameraSession? commitSession() {
    if (_session?.target == null) return null;
    
    final session = _session!;
    _session = null;
    notifyListeners();
    return session;
  }

  EditCameraSession? commitEditSession() {
    if (_editSession == null) return null;
    
    final session = _editSession!;
    _editSession = null;
    notifyListeners();
    return session;
  }
}
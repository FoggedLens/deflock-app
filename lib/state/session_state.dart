import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/node_profile.dart';
import '../models/operator_profile.dart';
import '../models/osm_node.dart';

// ------------------ AddNodeSession ------------------
class AddNodeSession {
  AddNodeSession({required this.profile, this.directionDegrees = 0});
  NodeProfile profile;
  OperatorProfile? operatorProfile;
  double directionDegrees;
  LatLng? target;
}

// ------------------ EditNodeSession ------------------
class EditNodeSession {
  EditNodeSession({
    required this.originalNode,
    required this.profile,
    required this.directionDegrees,
    required this.target,
  });
  
  final OsmNode originalNode; // The original node being edited
  NodeProfile profile;
  OperatorProfile? operatorProfile;
  double directionDegrees;
  LatLng target; // Current position (can be dragged)
}

class SessionState extends ChangeNotifier {
  AddNodeSession? _session;
  EditNodeSession? _editSession;

  // Getters
  AddNodeSession? get session => _session;
  EditNodeSession? get editSession => _editSession;

  void startAddSession(List<NodeProfile> enabledProfiles) {
    final submittableProfiles = enabledProfiles.where((p) => p.isSubmittable).toList();
    final defaultProfile = submittableProfiles.isNotEmpty 
        ? submittableProfiles.first 
        : enabledProfiles.first; // Fallback to any enabled profile
    _session = AddNodeSession(profile: defaultProfile);
    _editSession = null; // Clear any edit session
    notifyListeners();
  }

  void startEditSession(OsmNode node, List<NodeProfile> enabledProfiles) {
    final submittableProfiles = enabledProfiles.where((p) => p.isSubmittable).toList();
    
    // Try to find a matching profile based on the node's tags
    NodeProfile matchingProfile = submittableProfiles.isNotEmpty 
        ? submittableProfiles.first 
        : enabledProfiles.first;
    
    // Attempt to find a better match by comparing tags
    for (final profile in submittableProfiles) {
      if (_profileMatchesTags(profile, node.tags)) {
        matchingProfile = profile;
        break;
      }
    }
    
    _editSession = EditNodeSession(
      originalNode: node,
      profile: matchingProfile,
      directionDegrees: node.directionDeg ?? 0,
      target: node.coord,
    );
    _session = null; // Clear any add session
    notifyListeners();
  }

  bool _profileMatchesTags(NodeProfile profile, Map<String, String> tags) {
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
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
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
    if (operatorProfile != _session!.operatorProfile) {
      _session!.operatorProfile = operatorProfile;
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
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
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
    if (operatorProfile != _editSession!.operatorProfile) {
      _editSession!.operatorProfile = operatorProfile;
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

  AddNodeSession? commitSession() {
    if (_session?.target == null) return null;
    
    final session = _session!;
    _session = null;
    notifyListeners();
    return session;
  }

  EditNodeSession? commitEditSession() {
    if (_editSession == null) return null;
    
    final session = _editSession!;
    _editSession = null;
    notifyListeners();
    return session;
  }
}
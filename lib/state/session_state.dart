import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/node_profile.dart';
import '../models/operator_profile.dart';
import '../models/osm_node.dart';

// ------------------ AddNodeSession ------------------
class AddNodeSession {
  NodeProfile? profile;
  OperatorProfile? operatorProfile;
  LatLng? target;
  List<double> directions;          // All directions [90, 180, 270]
  int currentDirectionIndex;        // Which direction we're editing (e.g. 1 = editing the 180°)
  
  AddNodeSession({
    this.profile, 
    double initialDirection = 0,
    this.operatorProfile,
    this.target,
  }) : directions = [initialDirection],
       currentDirectionIndex = 0;
  
  // Slider always shows the current direction being edited
  double get directionDegrees => directions[currentDirectionIndex];
  set directionDegrees(double value) => directions[currentDirectionIndex] = value;
}

// ------------------ EditNodeSession ------------------
class EditNodeSession {
  final OsmNode originalNode; // The original node being edited
  NodeProfile? profile;
  OperatorProfile? operatorProfile;
  LatLng target; // Current position (can be dragged)
  List<double> directions;          // All directions [90, 180, 270]
  int currentDirectionIndex;        // Which direction we're editing (e.g. 1 = editing the 180°)
  
  EditNodeSession({
    required this.originalNode,
    this.profile,
    required double initialDirection,
    required this.target,
  }) : directions = [initialDirection],
       currentDirectionIndex = 0;
  
  // Slider always shows the current direction being edited
  double get directionDegrees => directions[currentDirectionIndex];
  set directionDegrees(double value) => directions[currentDirectionIndex] = value;
}

class SessionState extends ChangeNotifier {
  AddNodeSession? _session;
  EditNodeSession? _editSession;

  // Getters
  AddNodeSession? get session => _session;
  EditNodeSession? get editSession => _editSession;

  void startAddSession(List<NodeProfile> enabledProfiles) {
    // Start with no profile selected - force user to choose
    _session = AddNodeSession();
    _editSession = null; // Clear any edit session
    notifyListeners();
  }

  void startEditSession(OsmNode node, List<NodeProfile> enabledProfiles) {
    final submittableProfiles = enabledProfiles.where((p) => p.isSubmittable).toList();
    
    // Try to find a matching profile based on the node's tags
    NodeProfile? matchingProfile;
    
    // Attempt to find a match by comparing tags
    for (final profile in submittableProfiles) {
      if (_profileMatchesTags(profile, node.tags)) {
        matchingProfile = profile;
        break;
      }
    }
    
    // Start with no profile selected if no match found - force user to choose
    // Initialize edit session with all existing directions
    final existingDirections = node.directionDeg.isNotEmpty ? node.directionDeg : [0.0];
    
    _editSession = EditNodeSession(
      originalNode: node,
      profile: matchingProfile,
      initialDirection: existingDirections.first,
      target: node.coord,
    );
    
    // Replace the default single direction with all existing directions
    _editSession!.directions = List<double>.from(existingDirections);
    _editSession!.currentDirectionIndex = 0; // Start editing the first direction
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

  // Add new direction at 0° and switch to editing it
  void addDirection() {
    if (_session != null) {
      _session!.directions.add(0.0);
      _session!.currentDirectionIndex = _session!.directions.length - 1;
      notifyListeners();
    } else if (_editSession != null) {
      _editSession!.directions.add(0.0);
      _editSession!.currentDirectionIndex = _editSession!.directions.length - 1;
      notifyListeners();
    }
  }

  // Remove currently selected direction
  void removeDirection() {
    if (_session != null && _session!.directions.length > 1) {
      _session!.directions.removeAt(_session!.currentDirectionIndex);
      if (_session!.currentDirectionIndex >= _session!.directions.length) {
        _session!.currentDirectionIndex = _session!.directions.length - 1;
      }
      notifyListeners();
    } else if (_editSession != null && _editSession!.directions.length > 1) {
      _editSession!.directions.removeAt(_editSession!.currentDirectionIndex);
      if (_editSession!.currentDirectionIndex >= _editSession!.directions.length) {
        _editSession!.currentDirectionIndex = _editSession!.directions.length - 1;
      }
      notifyListeners();
    }
  }

  // Cycle to next direction
  void cycleDirection() {
    if (_session != null && _session!.directions.length > 1) {
      _session!.currentDirectionIndex = (_session!.currentDirectionIndex + 1) % _session!.directions.length;
      notifyListeners();
    } else if (_editSession != null && _editSession!.directions.length > 1) {
      _editSession!.currentDirectionIndex = (_editSession!.currentDirectionIndex + 1) % _editSession!.directions.length;
      notifyListeners();
    }
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
    if (_session?.target == null || _session?.profile == null) return null;
    
    final session = _session!;
    _session = null;
    notifyListeners();
    return session;
  }

  EditNodeSession? commitEditSession() {
    if (_editSession?.profile == null) return null;
    
    final session = _editSession!;
    _editSession = null;
    notifyListeners();
    return session;
  }
}
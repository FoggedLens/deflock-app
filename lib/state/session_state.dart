import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/node_profile.dart';
import '../models/operator_profile.dart';
import '../models/osm_node.dart';
import '../models/pending_upload.dart'; // For UploadOperation enum

// ------------------ AddNodeSession ------------------
class AddNodeSession {
  NodeProfile? profile;
  OperatorProfile? operatorProfile;
  LatLng? target;
  List<double> directions;          // All directions [90, 180, 270]
  int currentDirectionIndex;        // Which direction we're editing (e.g. 1 = editing the 180°)
  Map<String, String> refinedTags;  // User-selected values for empty profile tags
  Map<String, String> additionalExistingTags; // For consistency (always empty for new nodes)
  String changesetComment;          // User-editable changeset comment
  
  AddNodeSession({
    this.profile, 
    double initialDirection = 0,
    this.operatorProfile,
    this.target,
    Map<String, String>? refinedTags,
    Map<String, String>? additionalExistingTags,
    String? changesetComment,
  }) : directions = [initialDirection],
       currentDirectionIndex = 0,
       refinedTags = refinedTags ?? {},
       additionalExistingTags = additionalExistingTags ?? {}, // Always empty for new nodes
       changesetComment = changesetComment ?? '';
  
  // Slider always shows the current direction being edited
  double get directionDegrees => directions.isNotEmpty && currentDirectionIndex >= 0 
      ? directions[currentDirectionIndex] 
      : 0.0;
  set directionDegrees(double value) {
    if (directions.isNotEmpty && currentDirectionIndex >= 0) {
      directions[currentDirectionIndex] = value;
    }
  }
}

// ------------------ EditNodeSession ------------------
class EditNodeSession {
  final OsmNode originalNode; // The original node being edited
  final bool originalHadDirections; // Whether original node had any directions
  NodeProfile? profile;
  OperatorProfile? operatorProfile;
  LatLng target; // Current position (can be dragged)
  List<double> directions;          // All directions [90, 180, 270]
  int currentDirectionIndex;        // Which direction we're editing (e.g. 1 = editing the 180°)
  bool extractFromWay; // True if user wants to extract this constrained node
  Map<String, String> refinedTags;  // User-selected values for empty profile tags
  Map<String, String> additionalExistingTags; // Tags that exist on node but not in profile
  String changesetComment;          // User-editable changeset comment
  
  EditNodeSession({
    required this.originalNode,
    required this.originalHadDirections,
    this.profile,
    this.operatorProfile,
    required double initialDirection,
    required this.target,
    this.extractFromWay = false,
    Map<String, String>? refinedTags,
    Map<String, String>? additionalExistingTags,
    String? changesetComment,
  }) : directions = [initialDirection],
       currentDirectionIndex = 0,
       refinedTags = refinedTags ?? {},
       additionalExistingTags = additionalExistingTags ?? {},
       changesetComment = changesetComment ?? '';
  
  // Slider always shows the current direction being edited
  double get directionDegrees => directions.isNotEmpty && currentDirectionIndex >= 0 
      ? directions[currentDirectionIndex] 
      : 0.0;
  set directionDegrees(double value) {
    if (directions.isNotEmpty && currentDirectionIndex >= 0) {
      directions[currentDirectionIndex] = value;
    }
  }
}

class SessionState extends ChangeNotifier {
  AddNodeSession? _session;
  EditNodeSession? _editSession;
  OperatorProfile? _detectedOperatorProfile; // Persists across profile changes

  // Getters
  AddNodeSession? get session => _session;
  EditNodeSession? get editSession => _editSession;

  void startAddSession(List<NodeProfile> enabledProfiles) {
    // Start with no profile selected - force user to choose
    _session = AddNodeSession(
      changesetComment: 'Add surveillance node', // Default comment, will be updated when profile is selected
    );
    _editSession = null; // Clear any edit session
    notifyListeners();
  }

  void startEditSession(OsmNode node, List<NodeProfile> enabledProfiles, List<OperatorProfile> operatorProfiles) {
    // Always create and pre-select the temporary "existing tags" profile (now empty)
    final existingTagsProfile = NodeProfile.createExistingTagsProfile(node);
    
    // Detect and store operator profile (persists across profile changes)
    _detectedOperatorProfile = OperatorProfile.createExistingOperatorProfile(node, operatorProfiles);
    
    // Initialize edit session with all existing directions, or empty list if none
    final existingDirections = node.directionDeg.isNotEmpty ? node.directionDeg : <double>[];
    final initialDirection = existingDirections.isNotEmpty ? existingDirections.first : 0.0;
    final originalHadDirections = existingDirections.isNotEmpty;
    
    // Since the "existing tags" profile is now empty, all existing node tags 
    // (minus special ones) should go into additionalExistingTags
    final initialAdditionalTags = _calculateAdditionalExistingTags(existingTagsProfile, node);
    
    // Auto-populate refined tags (empty profile means no refined tags initially)
    final initialRefinedTags = _calculateRefinedTags(existingTagsProfile, node);
    
    _editSession = EditNodeSession(
      originalNode: node,
      originalHadDirections: originalHadDirections,
      profile: existingTagsProfile,
      operatorProfile: _detectedOperatorProfile,
      initialDirection: initialDirection,
      target: node.coord,
      additionalExistingTags: initialAdditionalTags,
      refinedTags: initialRefinedTags,
      changesetComment: 'Update a surveillance node', // Default comment for existing tags profile
    );
    
    // Replace the default single direction with all existing directions (or empty list)
    _editSession!.directions = List<double>.from(existingDirections);
    _editSession!.currentDirectionIndex = existingDirections.isNotEmpty ? 0 : -1; // -1 indicates no directions
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

  /// Calculate additional existing tags for a given profile change
  Map<String, String> _calculateAdditionalExistingTags(NodeProfile? newProfile, OsmNode originalNode) {
    final additionalTags = <String, String>{};
    
    // Skip if no profile
    if (newProfile == null) {
      return additionalTags;
    }
    
    // Get tags from the original node that are not in the selected profile
    final profileTagKeys = newProfile.tags.keys.toSet();
    final originalTags = originalNode.tags;
    
    for (final entry in originalTags.entries) {
      final key = entry.key;
      final value = entry.value;
      
      // Skip tags that are handled elsewhere
      if (_shouldSkipTag(key)) continue;
      
      // Skip tags that exist in the selected profile
      if (profileTagKeys.contains(key)) continue;
      
      // Include this tag as an additional existing tag
      additionalTags[key] = value;
    }
    
    return additionalTags;
  }
  
  /// Auto-populate refined tags with existing values from the original node
  Map<String, String> _calculateRefinedTags(NodeProfile? profile, OsmNode originalNode) {
    final refinedTags = <String, String>{};
    
    if (profile == null) return refinedTags;
    
    // For each empty-value tag in the profile, check if original node has a value
    for (final entry in profile.tags.entries) {
      final tagKey = entry.key;
      final profileValue = entry.value;
      
      // Only auto-populate if profile tag value is empty
      if (profileValue.trim().isEmpty) {
        final existingValue = originalNode.tags[tagKey];
        if (existingValue != null && existingValue.trim().isNotEmpty) {
          refinedTags[tagKey] = existingValue;
        }
      }
    }
    
    return refinedTags;
  }
  
  /// Check if a tag should be skipped from additional existing tags
  bool _shouldSkipTag(String key) {
    // Skip direction tags (handled separately)
    if (key == 'direction' || key == 'camera:direction') return true;
    
    // Skip operator tags (handled by operator profile)
    if (key == 'operator' || key.startsWith('operator:')) return true;
    
    // Skip internal cache tags
    if (key.startsWith('_')) return true;
    
    return false;
  }

  void updateSession({
    double? directionDeg,
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
    LatLng? target,
    Map<String, String>? refinedTags,
    Map<String, String>? additionalExistingTags,
    String? changesetComment,
  }) {
    if (_session == null) return;

    bool dirty = false;
    if (directionDeg != null && directionDeg != _session!.directionDegrees) {
      _session!.directionDegrees = directionDeg;
      dirty = true;
    }
    if (profile != null && profile != _session!.profile) {
      _session!.profile = profile;
      // Regenerate changeset comment when profile changes
      _session!.changesetComment = _generateDefaultChangesetComment(
        profile: profile,
        operation: UploadOperation.create,
      );
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
    if (refinedTags != null) {
      _session!.refinedTags = Map<String, String>.from(refinedTags);
      dirty = true;
    }
    if (additionalExistingTags != null) {
      _session!.additionalExistingTags = Map<String, String>.from(additionalExistingTags);
      dirty = true;
    }
    if (changesetComment != null) {
      _session!.changesetComment = changesetComment;
      dirty = true;
    }
    if (dirty) notifyListeners();
  }

  void updateEditSession({
    double? directionDeg,
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
    LatLng? target,
    bool? extractFromWay,
    Map<String, String>? refinedTags,
    Map<String, String>? additionalExistingTags,
    String? changesetComment,
  }) {
    if (_editSession == null) return;

    bool dirty = false;
    bool snapBackRequired = false;
    LatLng? snapBackTarget;
    
    if (directionDeg != null && directionDeg != _editSession!.directionDegrees) {
      _editSession!.directionDegrees = directionDeg;
      dirty = true;
    }
    if (profile != null && profile != _editSession!.profile) {
      final oldProfile = _editSession!.profile;
      _editSession!.profile = profile;
      
      // Handle direction requirements when profile changes
      _handleDirectionRequirementsOnProfileChange(oldProfile, profile);
      
      // When profile changes but operator profile not explicitly provided,
      // restore the detected operator profile (if any)
      if (operatorProfile == null && _detectedOperatorProfile != null) {
        _editSession!.operatorProfile = _detectedOperatorProfile;
      }
      
      // Calculate additional existing tags for non-existing-tags profiles
      // Only do this if additionalExistingTags wasn't explicitly provided
      if (additionalExistingTags == null) {
        _editSession!.additionalExistingTags = _calculateAdditionalExistingTags(profile, _editSession!.originalNode);
      }
      
      // Auto-populate refined tags with existing values for empty profile tags
      // Only do this if refinedTags wasn't explicitly provided
      if (refinedTags == null) {
        _editSession!.refinedTags = _calculateRefinedTags(profile, _editSession!.originalNode);
      }
      
      // Regenerate changeset comment when profile changes
      final operation = _editSession!.extractFromWay ? UploadOperation.extract : UploadOperation.modify;
      _editSession!.changesetComment = _generateDefaultChangesetComment(
        profile: profile,
        operation: operation,
      );
      
      dirty = true;
    }
    // Only update operator profile if explicitly provided (including null) and different from current
    if (operatorProfile != _editSession!.operatorProfile) {
      _editSession!.operatorProfile = operatorProfile; // This can be null
      dirty = true;
    }
    if (target != null && target != _editSession!.target) {
      _editSession!.target = target;
      dirty = true;
    }
    if (extractFromWay != null && extractFromWay != _editSession!.extractFromWay) {
      _editSession!.extractFromWay = extractFromWay;
      // When extract is unchecked, snap back to original location
      if (!extractFromWay) {
        _editSession!.target = _editSession!.originalNode.coord;
        snapBackRequired = true;
        snapBackTarget = _editSession!.originalNode.coord;
      }
      dirty = true;
    }
    if (refinedTags != null) {
      _editSession!.refinedTags = Map<String, String>.from(refinedTags);
      dirty = true;
    }
    if (additionalExistingTags != null) {
      _editSession!.additionalExistingTags = Map<String, String>.from(additionalExistingTags);
      dirty = true;
    }
    if (changesetComment != null) {
      _editSession!.changesetComment = changesetComment;
      dirty = true;
    }
    
    if (dirty) notifyListeners();
    
    // Store snap back info for map view to pick up
    if (snapBackRequired && snapBackTarget != null) {
      _pendingSnapBack = snapBackTarget;
    }
  }

  // For map view to check and consume snap back requests
  LatLng? _pendingSnapBack;
  LatLng? consumePendingSnapBack() {
    final result = _pendingSnapBack;
    _pendingSnapBack = null;
    return result;
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
    if (_session != null && _session!.directions.isNotEmpty) {
      // For add sessions, keep minimum of 1 direction
      if (_session!.directions.length > 1) {
        _session!.directions.removeAt(_session!.currentDirectionIndex);
        if (_session!.currentDirectionIndex >= _session!.directions.length) {
          _session!.currentDirectionIndex = _session!.directions.length - 1;
        }
        notifyListeners();
      }
    } else if (_editSession != null && _editSession!.directions.isNotEmpty) {
      // For edit sessions, use minimum calculation
      final minDirections = _getMinimumDirections();
      
      if (_editSession!.directions.length > minDirections) {
        _editSession!.directions.removeAt(_editSession!.currentDirectionIndex);
        if (_editSession!.directions.isEmpty) {
          _editSession!.currentDirectionIndex = -1; // No directions
        } else if (_editSession!.currentDirectionIndex >= _editSession!.directions.length) {
          _editSession!.currentDirectionIndex = _editSession!.directions.length - 1;
        }
        notifyListeners();
      }
    }
  }

  // Cycle to next direction
  void cycleDirection() {
    if (_session != null && _session!.directions.length > 1) {
      _session!.currentDirectionIndex = (_session!.currentDirectionIndex + 1) % _session!.directions.length;
      notifyListeners();
    } else if (_editSession != null && _editSession!.directions.length > 1 && _editSession!.currentDirectionIndex >= 0) {
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
    _detectedOperatorProfile = null;
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
    _detectedOperatorProfile = null;
    notifyListeners();
    return session;
  }

  /// Get the minimum number of directions required for current session state
  int _getMinimumDirections() {
    if (_editSession == null) return 1;
    
    // Minimum = 0 only if original node had no directions
    // Allow preserving the original state (directionless nodes can stay directionless)
    return _editSession!.originalHadDirections ? 1 : 0;
  }

  /// Check if remove direction button should be enabled for edit session
  bool get canRemoveDirection {
    if (_editSession == null || _editSession!.directions.isEmpty) return false;
    return _editSession!.directions.length > _getMinimumDirections();
  }

  /// Handle direction requirements when profile changes in edit session
  void _handleDirectionRequirementsOnProfileChange(NodeProfile? oldProfile, NodeProfile newProfile) {
    if (_editSession == null) return;
    
    final minimum = _getMinimumDirections();
    
    // Ensure we meet the minimum (add direction if needed)
    if (_editSession!.directions.length < minimum) {
      _editSession!.directions = [0.0];
      _editSession!.currentDirectionIndex = 0;
    }
  }

  /// Generate a default changeset comment for a submission
  /// Handles special case of <Existing tags> profile by using "a" instead
  String _generateDefaultChangesetComment({
    required NodeProfile? profile,
    required UploadOperation operation,
  }) {
    // Handle temp profiles with brackets by using "a"
    final profileName = profile?.name.startsWith('<') == true && profile?.name.endsWith('>') == true
        ? 'a'
        : profile?.name ?? 'surveillance';
    
    switch (operation) {
      case UploadOperation.create:
        return 'Add $profileName surveillance node';
      case UploadOperation.modify:
        return 'Update $profileName surveillance node'; 
      case UploadOperation.delete:
        return 'Delete $profileName surveillance node';
      case UploadOperation.extract:
        return 'Extract $profileName surveillance node';
    }
  }
}
import 'package:latlong2/latlong.dart';
import 'node_profile.dart';
import 'operator_profile.dart';
import '../state/settings_state.dart';

enum UploadOperation { create, modify, delete }

class PendingUpload {
  final LatLng coord;
  final double direction;
  final NodeProfile profile;
  final OperatorProfile? operatorProfile;
  final UploadMode uploadMode; // Capture upload destination when queued
  final UploadOperation operation; // Type of operation: create, modify, or delete
  final int? originalNodeId; // If this is modify/delete, the ID of the original OSM node
  int? submittedNodeId; // The actual node ID returned by OSM after successful submission
  int attempts;
  bool error;
  bool completing; // True when upload succeeded but item is showing checkmark briefly

  PendingUpload({
    required this.coord,
    required this.direction,
    required this.profile,
    this.operatorProfile,
    required this.uploadMode,
    required this.operation,
    this.originalNodeId,
    this.submittedNodeId,
    this.attempts = 0,
    this.error = false,
    this.completing = false,
  }) : assert(
         (operation == UploadOperation.create && originalNodeId == null) ||
         (operation != UploadOperation.create && originalNodeId != null),
         'originalNodeId must be null for create operations and non-null for modify/delete operations'
       );

  // True if this is an edit of an existing node, false if it's a new node
  bool get isEdit => operation == UploadOperation.modify;
  
  // True if this is a deletion of an existing node
  bool get isDeletion => operation == UploadOperation.delete;

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

  // Get combined tags from node profile and operator profile
  Map<String, String> getCombinedTags() {
    final tags = Map<String, String>.from(profile.tags);
    
    // Add operator profile tags (they override node profile tags if there are conflicts)
    if (operatorProfile != null) {
      tags.addAll(operatorProfile!.tags);
    }
    
    // Add direction if required
    if (profile.requiresDirection) {
      tags['direction'] = direction.toStringAsFixed(0);
    }
    
    return tags;
  }

  Map<String, dynamic> toJson() => {
        'lat': coord.latitude,
        'lon': coord.longitude,
        'dir': direction,
        'profile': profile.toJson(),
        'operatorProfile': operatorProfile?.toJson(),
        'uploadMode': uploadMode.index,
        'operation': operation.index,
        'originalNodeId': originalNodeId,
        'submittedNodeId': submittedNodeId,
        'attempts': attempts,
        'error': error,
        'completing': completing,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        coord: LatLng(j['lat'], j['lon']),
        direction: j['dir'],
        profile: j['profile'] is Map<String, dynamic>
            ? NodeProfile.fromJson(j['profile'])
            : NodeProfile.genericAlpr(),
        operatorProfile: j['operatorProfile'] != null
            ? OperatorProfile.fromJson(j['operatorProfile'])
            : null,
        uploadMode: j['uploadMode'] != null 
            ? UploadMode.values[j['uploadMode']] 
            : UploadMode.production, // Default for legacy entries
        operation: j['operation'] != null
            ? UploadOperation.values[j['operation']]
            : (j['originalNodeId'] != null ? UploadOperation.modify : UploadOperation.create), // Legacy compatibility
        originalNodeId: j['originalNodeId'],
        submittedNodeId: j['submittedNodeId'],
        attempts: j['attempts'] ?? 0,
        error: j['error'] ?? false,
        completing: j['completing'] ?? false, // Default to false for legacy entries
      );
}


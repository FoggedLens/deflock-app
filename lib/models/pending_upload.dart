import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'node_profile.dart';
import 'operator_profile.dart';
import '../state/settings_state.dart';
import '../dev_config.dart';

enum UploadOperation { create, modify, delete, extract }

enum UploadState { 
  pending,           // Not started yet
  creatingChangeset, // Creating changeset
  uploading,         // Node operation (create/modify/delete)
  closingChangeset,  // Closing changeset
  error,             // Upload failed (needs user retry) OR changeset not found
  complete           // Everything done
}

class PendingUpload {
  final LatLng coord;
  final dynamic direction; // Can be double or String for multiple directions
  final NodeProfile? profile;
  final OperatorProfile? operatorProfile;
  final Map<String, String> refinedTags; // User-selected values for empty profile tags
  final UploadMode uploadMode; // Capture upload destination when queued
  final UploadOperation operation; // Type of operation: create, modify, or delete
  final int? originalNodeId; // If this is modify/delete, the ID of the original OSM node
  int? submittedNodeId; // The actual node ID returned by OSM after successful submission
  int? tempNodeId; // ID of temporary node created in cache (for specific cleanup)
  int attempts;
  bool error; // DEPRECATED: Use uploadState instead
  String? errorMessage; // Detailed error message for debugging
  bool completing; // DEPRECATED: Use uploadState instead
  UploadState uploadState; // Current state in the upload pipeline
  String? changesetId; // ID of changeset that needs closing
  DateTime? nodeOperationCompletedAt; // When node operation completed (start of 59-minute countdown)
  int changesetCloseAttempts; // Number of changeset close attempts
  DateTime? lastChangesetCloseAttemptAt; // When we last tried to close changeset (for retry timing)
  int nodeSubmissionAttempts; // Number of node submission attempts (separate from overall attempts)
  DateTime? lastNodeSubmissionAttemptAt; // When we last tried to submit node (for retry timing)

  PendingUpload({
    required this.coord,
    required this.direction,
    this.profile,
    this.operatorProfile,
    Map<String, String>? refinedTags,
    required this.uploadMode,
    required this.operation,
    this.originalNodeId,
    this.submittedNodeId,
    this.tempNodeId,
    this.attempts = 0,
    this.error = false,
    this.errorMessage,
    this.completing = false,
    this.uploadState = UploadState.pending,
    this.changesetId,
    this.nodeOperationCompletedAt,
    this.changesetCloseAttempts = 0,
    this.lastChangesetCloseAttemptAt,
    this.nodeSubmissionAttempts = 0,
    this.lastNodeSubmissionAttemptAt,
  }) : refinedTags = refinedTags ?? {},
       assert(
         (operation == UploadOperation.create && originalNodeId == null) ||
         (operation == UploadOperation.create) || (originalNodeId != null),
         'originalNodeId must be null for create operations and non-null for modify/delete/extract operations'
       ),
       assert(
         (operation == UploadOperation.delete) || (profile != null),
         'profile is required for create, modify, and extract operations'
       );

  // True if this is an edit of an existing node, false if it's a new node
  bool get isEdit => operation == UploadOperation.modify;
  
  // True if this is a deletion of an existing node
  bool get isDeletion => operation == UploadOperation.delete;
  
  // True if this is an extract operation (new node with tags from constrained node)
  bool get isExtraction => operation == UploadOperation.extract;
  
  // New state-based helpers
  bool get needsUserRetry => uploadState == UploadState.error;
  bool get isActivelyProcessing => uploadState == UploadState.creatingChangeset || uploadState == UploadState.uploading || uploadState == UploadState.closingChangeset;
  bool get isComplete => uploadState == UploadState.complete;
  bool get isPending => uploadState == UploadState.pending;
  bool get isCreatingChangeset => uploadState == UploadState.creatingChangeset;
  bool get isUploading => uploadState == UploadState.uploading;
  bool get isClosingChangeset => uploadState == UploadState.closingChangeset;
  
  // Calculate time until OSM auto-closes changeset (for UI display)  
  // This uses nodeOperationCompletedAt (when changeset was created) as the reference
  Duration? get timeUntilAutoClose {
    if (nodeOperationCompletedAt == null) return null;
    final elapsed = DateTime.now().difference(nodeOperationCompletedAt!);
    final remaining = kChangesetAutoCloseTimeout - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
  
  // Check if the 59-minute window has expired (for phases 2 & 3)
  // This uses nodeOperationCompletedAt (when changeset was created) as the reference
  bool get hasChangesetExpired {
    if (nodeOperationCompletedAt == null) return false;
    return DateTime.now().difference(nodeOperationCompletedAt!) >= kChangesetAutoCloseTimeout;
  }
  
  // Legacy method name for backward compatibility
  bool get shouldGiveUpOnChangeset => hasChangesetExpired;
  
  // Calculate next retry delay for changeset close using exponential backoff
  Duration get nextChangesetCloseRetryDelay {
    final delay = Duration(
      milliseconds: (kChangesetCloseInitialRetryDelay.inMilliseconds * 
                     math.pow(kChangesetCloseBackoffMultiplier, changesetCloseAttempts)).round()
    );
    return delay > kChangesetCloseMaxRetryDelay 
      ? kChangesetCloseMaxRetryDelay 
      : delay;
  }

  // Check if it's time to retry changeset close
  bool get isReadyForChangesetCloseRetry {
    if (lastChangesetCloseAttemptAt == null) return true; // First attempt
    
    final nextRetryTime = lastChangesetCloseAttemptAt!.add(nextChangesetCloseRetryDelay);
    return DateTime.now().isAfter(nextRetryTime);
  }

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

  // Set error state with detailed message
  void setError(String message) {
    error = true; // Keep for backward compatibility
    uploadState = UploadState.error;
    errorMessage = message;
  }

  // Clear error state
  void clearError() {
    error = false; // Keep for backward compatibility
    uploadState = UploadState.pending;
    errorMessage = null;
    attempts = 0;
    changesetCloseAttempts = 0;
    changesetId = null;
    nodeOperationCompletedAt = null;
    lastChangesetCloseAttemptAt = null;
    nodeSubmissionAttempts = 0;
    lastNodeSubmissionAttemptAt = null;
  }

  // Mark as creating changeset
  void markAsCreatingChangeset() {
    uploadState = UploadState.creatingChangeset;
    error = false;
    completing = false;
    errorMessage = null;
  }

  // Mark changeset created, start node operation
  void markChangesetCreated(String csId) {
    uploadState = UploadState.uploading;
    changesetId = csId;
    nodeOperationCompletedAt = DateTime.now(); // Track when changeset was created for 59-minute timeout
  }

  // Mark node operation as complete, start changeset close phase
  void markNodeOperationComplete() {
    uploadState = UploadState.closingChangeset;
    changesetCloseAttempts = 0;
    // Note: nodeSubmissionAttempts preserved for debugging/stats
  }

  // Mark entire upload as complete
  void markAsComplete() {
    uploadState = UploadState.complete;
    completing = true; // Keep for UI compatibility
    error = false;
    errorMessage = null;
  }

  // Increment changeset close attempt counter and record attempt time
  void incrementChangesetCloseAttempts() {
    changesetCloseAttempts++;
    lastChangesetCloseAttemptAt = DateTime.now();
  }

  // Increment node submission attempt counter and record attempt time
  void incrementNodeSubmissionAttempts() {
    nodeSubmissionAttempts++;
    lastNodeSubmissionAttemptAt = DateTime.now();
  }

  // Calculate next retry delay for node submission using exponential backoff
  Duration get nextNodeSubmissionRetryDelay {
    final delay = Duration(
      milliseconds: (kChangesetCloseInitialRetryDelay.inMilliseconds * 
                     math.pow(kChangesetCloseBackoffMultiplier, nodeSubmissionAttempts)).round()
    );
    return delay > kChangesetCloseMaxRetryDelay 
      ? kChangesetCloseMaxRetryDelay 
      : delay;
  }

  // Check if it's time to retry node submission
  bool get isReadyForNodeSubmissionRetry {
    if (lastNodeSubmissionAttemptAt == null) return true; // First attempt
    
    final nextRetryTime = lastNodeSubmissionAttemptAt!.add(nextNodeSubmissionRetryDelay);
    return DateTime.now().isAfter(nextRetryTime);
  }

  // Get combined tags from node profile, operator profile, and refined tags
  Map<String, String> getCombinedTags() {
    // Deletions don't need tags
    if (operation == UploadOperation.delete || profile == null) {
      return {};
    }
    
    final tags = Map<String, String>.from(profile!.tags);
    
    // Apply refined tags (these fill in empty values from the profile)
    for (final entry in refinedTags.entries) {
      // Only apply refined tags if the profile tag value is empty
      if (tags.containsKey(entry.key) && tags[entry.key]?.trim().isEmpty == true) {
        tags[entry.key] = entry.value;
      }
    }
    
    // Add operator profile tags (they override node profile tags if there are conflicts)
    if (operatorProfile != null) {
      tags.addAll(operatorProfile!.tags);
    }
    
    // Add direction if required
    if (profile!.requiresDirection) {
      if (direction is String) {
        tags['direction'] = direction;
      } else if (direction is double) {
        tags['direction'] = direction.toStringAsFixed(0);
      } else {
        tags['direction'] = '0';
      }
    }
    
    // Filter out any tags that are still empty after refinement
    // Empty tags in profiles are fine for refinement UI, but shouldn't be submitted to OSM
    tags.removeWhere((key, value) => value.trim().isEmpty);
    
    return tags;
  }

  Map<String, dynamic> toJson() => {
        'lat': coord.latitude,
        'lon': coord.longitude,
        'dir': direction,
        'profile': profile?.toJson(),
        'operatorProfile': operatorProfile?.toJson(),
        'refinedTags': refinedTags,
        'uploadMode': uploadMode.index,
        'operation': operation.index,
        'originalNodeId': originalNodeId,
        'submittedNodeId': submittedNodeId,
        'tempNodeId': tempNodeId,
        'attempts': attempts,
        'error': error,
        'errorMessage': errorMessage,
        'completing': completing,
        'uploadState': uploadState.index,
        'changesetId': changesetId,
        'nodeOperationCompletedAt': nodeOperationCompletedAt?.millisecondsSinceEpoch,
        'changesetCloseAttempts': changesetCloseAttempts,
        'lastChangesetCloseAttemptAt': lastChangesetCloseAttemptAt?.millisecondsSinceEpoch,
        'nodeSubmissionAttempts': nodeSubmissionAttempts,
        'lastNodeSubmissionAttemptAt': lastNodeSubmissionAttemptAt?.millisecondsSinceEpoch,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        coord: LatLng(j['lat'], j['lon']),
        direction: j['dir'],
        profile: j['profile'] is Map<String, dynamic>
            ? NodeProfile.fromJson(j['profile'])
            : null, // Profile is optional for deletions
        operatorProfile: j['operatorProfile'] != null
            ? OperatorProfile.fromJson(j['operatorProfile'])
            : null,
        refinedTags: j['refinedTags'] != null 
            ? Map<String, String>.from(j['refinedTags'])
            : {}, // Default empty map for legacy entries
        uploadMode: j['uploadMode'] != null 
            ? UploadMode.values[j['uploadMode']] 
            : UploadMode.production, // Default for legacy entries
        operation: j['operation'] != null
            ? UploadOperation.values[j['operation']]
            : (j['originalNodeId'] != null ? UploadOperation.modify : UploadOperation.create), // Legacy compatibility
        originalNodeId: j['originalNodeId'],
        submittedNodeId: j['submittedNodeId'],
        tempNodeId: j['tempNodeId'],
        attempts: j['attempts'] ?? 0,
        error: j['error'] ?? false,
        errorMessage: j['errorMessage'], // Can be null for legacy entries
        completing: j['completing'] ?? false, // Default to false for legacy entries
        uploadState: j['uploadState'] != null
            ? UploadState.values[j['uploadState']]
            : _migrateFromLegacyFields(j), // Migrate from legacy error/completing fields
        changesetId: j['changesetId'],
        nodeOperationCompletedAt: j['nodeOperationCompletedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['nodeOperationCompletedAt'])
            : null,
        changesetCloseAttempts: j['changesetCloseAttempts'] ?? 0,
        lastChangesetCloseAttemptAt: j['lastChangesetCloseAttemptAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['lastChangesetCloseAttemptAt'])
            : null,
        nodeSubmissionAttempts: j['nodeSubmissionAttempts'] ?? 0,
        lastNodeSubmissionAttemptAt: j['lastNodeSubmissionAttemptAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['lastNodeSubmissionAttemptAt'])
            : null,
      );

  // Helper to migrate legacy queue items to new state system
  static UploadState _migrateFromLegacyFields(Map<String, dynamic> j) {
    final error = j['error'] ?? false;
    final completing = j['completing'] ?? false;
    
    if (completing) return UploadState.complete;
    if (error) return UploadState.error;
    return UploadState.pending;
  }
}


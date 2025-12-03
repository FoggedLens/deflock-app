import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

import '../models/pending_upload.dart';
import '../models/osm_node.dart';
import '../models/node_profile.dart';
import '../services/node_cache.dart';
import '../services/uploader.dart';
import '../widgets/node_provider_with_cache.dart';
import 'settings_state.dart';
import 'session_state.dart';

class UploadQueueState extends ChangeNotifier {
  final List<PendingUpload> _queue = [];
  Timer? _uploadTimer;

  // Getters
  int get pendingCount => _queue.length;
  List<PendingUpload> get pendingUploads => List.unmodifiable(_queue);

  // Initialize by loading queue from storage and repopulate cache with pending nodes
  Future<void> init() async {
    await _loadQueue();
    print('[UploadQueue] Loaded ${_queue.length} items from storage');
    _repopulateCacheFromQueue();
  }

  // Repopulate the cache with pending nodes from the queue on startup
  void _repopulateCacheFromQueue() {
    print('[UploadQueue] Repopulating cache from ${_queue.length} queue items');
    final nodesToAdd = <OsmNode>[];
    
    for (final upload in _queue) {
      // Skip completed uploads - they should already be in OSM and will be fetched normally
      if (upload.isComplete) {
        print('[UploadQueue] Skipping completed upload at ${upload.coord}');
        continue;
      }
      
      print('[UploadQueue] Processing ${upload.operation} upload at ${upload.coord}');
      
      if (upload.isDeletion) {
        // For deletions: mark the original node as pending deletion if it exists in cache
        if (upload.originalNodeId != null) {
          final existingNode = NodeCache.instance.getNodeById(upload.originalNodeId!);
          if (existingNode != null) {
            final deletionTags = Map<String, String>.from(existingNode.tags);
            deletionTags['_pending_deletion'] = 'true';
            
            final nodeWithDeletionTag = OsmNode(
              id: upload.originalNodeId!,
              coord: existingNode.coord,
              tags: deletionTags,
            );
            nodesToAdd.add(nodeWithDeletionTag);
          }
        }
      } else {
        // For creates, edits, and extracts: recreate temp node if needed
        // Generate new temp ID if not already stored (for backward compatibility)
        final tempId = upload.tempNodeId ?? -DateTime.now().millisecondsSinceEpoch - _queue.indexOf(upload);
        
        final tags = upload.getCombinedTags();
        tags['_pending_upload'] = 'true';
        tags['_temp_id'] = tempId.toString();
        
        // Store temp ID for future cleanup if not already set
        if (upload.tempNodeId == null) {
          upload.tempNodeId = tempId;
        }
        
        if (upload.isEdit) {
          // For edits: also mark original with _pending_edit if it exists
          if (upload.originalNodeId != null) {
            final existingOriginal = NodeCache.instance.getNodeById(upload.originalNodeId!);
            if (existingOriginal != null) {
              final originalTags = Map<String, String>.from(existingOriginal.tags);
              originalTags['_pending_edit'] = 'true';
              
              final originalWithEdit = OsmNode(
                id: upload.originalNodeId!,
                coord: existingOriginal.coord,
                tags: originalTags,
              );
              nodesToAdd.add(originalWithEdit);
            }
          }
          
          // Add connection line marker
          tags['_original_node_id'] = upload.originalNodeId.toString();
        } else if (upload.operation == UploadOperation.extract) {
          // For extracts: add connection line marker
          tags['_original_node_id'] = upload.originalNodeId.toString();
        }
        
        final tempNode = OsmNode(
          id: tempId,
          coord: upload.coord,
          tags: tags,
        );
        nodesToAdd.add(tempNode);
      }
    }
    
    if (nodesToAdd.isNotEmpty) {
      NodeCache.instance.addOrUpdate(nodesToAdd);
      print('[UploadQueue] Repopulated cache with ${nodesToAdd.length} pending nodes from queue');
      
      // Save queue if we updated any temp IDs for backward compatibility
      _saveQueue();
      
      // Notify node provider to update the map
      NodeProviderWithCache.instance.notifyListeners();
    }
  }

  // Add a completed session to the upload queue
  void addFromSession(AddNodeSession session, {required UploadMode uploadMode}) {
    final upload = PendingUpload(
      coord: session.target!,
      direction: _formatDirectionsForSubmission(session.directions, session.profile),
      profile: session.profile!,  // Safe to use ! because commitSession() checks for null
      operatorProfile: session.operatorProfile,
      uploadMode: uploadMode,
      operation: UploadOperation.create,
    );
    
    _queue.add(upload);
    _saveQueue();
    
    // Add to node cache immediately so it shows on the map
    // Create a temporary node with a negative ID (to distinguish from real OSM nodes)
    // Using timestamp as negative ID to ensure uniqueness
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tags = upload.getCombinedTags();
    tags['_pending_upload'] = 'true'; // Mark as pending for potential UI distinction
    tags['_temp_id'] = tempId.toString(); // Store temp ID for specific removal
    
    // Store the temp ID in the upload for cleanup purposes
    upload.tempNodeId = tempId;
    
    final tempNode = OsmNode(
      id: tempId,
      coord: upload.coord,
      tags: tags,
    );
    
    NodeCache.instance.addOrUpdate([tempNode]);
    // Notify node provider to update the map
    NodeProviderWithCache.instance.notifyListeners();
    
    notifyListeners();
  }

  // Add a completed edit session to the upload queue
  void addFromEditSession(EditNodeSession session, {required UploadMode uploadMode}) {
    // Determine operation type and coordinates
    final UploadOperation operation;
    final LatLng coordToUse;
    
    if (session.extractFromWay && session.originalNode.isConstrained) {
      // Extract operation: create new node at new location
      operation = UploadOperation.extract;
      coordToUse = session.target;
    } else if (session.originalNode.isConstrained) {
      // Constrained node without extract: use original position
      operation = UploadOperation.modify;
      coordToUse = session.originalNode.coord;
    } else {
      // Unconstrained node: normal modify operation
      operation = UploadOperation.modify;
      coordToUse = session.target;
    }
    
    final upload = PendingUpload(
      coord: coordToUse,
      direction: _formatDirectionsForSubmission(session.directions, session.profile),
      profile: session.profile!,  // Safe to use ! because commitEditSession() checks for null
      operatorProfile: session.operatorProfile,
      uploadMode: uploadMode,
      operation: operation,
      originalNodeId: session.originalNode.id, // Track which node we're editing
    );
    
    _queue.add(upload);
    _saveQueue();
    
    // Create cache entries based on operation type:
    if (operation == UploadOperation.extract) {
      // For extract: only create new node, leave original unchanged
      final tempId = -DateTime.now().millisecondsSinceEpoch;
      final extractedTags = upload.getCombinedTags();
      extractedTags['_pending_upload'] = 'true'; // Mark as pending upload
      extractedTags['_original_node_id'] = session.originalNode.id.toString(); // Track original for line drawing
      extractedTags['_temp_id'] = tempId.toString(); // Store temp ID for specific removal
      
      // Store the temp ID in the upload for cleanup purposes
      upload.tempNodeId = tempId;
      
      final extractedNode = OsmNode(
        id: tempId,
        coord: upload.coord, // At new location
        tags: extractedTags,
      );
      
      NodeCache.instance.addOrUpdate([extractedNode]);
    } else {
      // For modify: mark original with grey ring and create new temp node
      // 1. Mark the original node with _pending_edit (grey ring) at original location
      final originalTags = Map<String, String>.from(session.originalNode.tags);
      originalTags['_pending_edit'] = 'true'; // Mark original as having pending edit
      
      final originalNode = OsmNode(
        id: session.originalNode.id,
        coord: session.originalNode.coord, // Keep at original location
        tags: originalTags,
      );
      
      // 2. Create new temp node for the edited node (purple ring) at new location
      final tempId = -DateTime.now().millisecondsSinceEpoch;
      final editedTags = upload.getCombinedTags();
      editedTags['_pending_upload'] = 'true'; // Mark as pending upload
      editedTags['_original_node_id'] = session.originalNode.id.toString(); // Track original for line drawing
      editedTags['_temp_id'] = tempId.toString(); // Store temp ID for specific removal
      
      // Store the temp ID in the upload for cleanup purposes
      upload.tempNodeId = tempId;
      
      final editedNode = OsmNode(
        id: tempId,
        coord: upload.coord, // At new location
        tags: editedTags,
      );
      
      NodeCache.instance.addOrUpdate([originalNode, editedNode]);
    }
    // Notify node provider to update the map
    NodeProviderWithCache.instance.notifyListeners();
    
    notifyListeners();
  }

  // Add a node deletion to the upload queue
  void addFromNodeDeletion(OsmNode node, {required UploadMode uploadMode}) {
    final upload = PendingUpload(
      coord: node.coord,
      direction: node.directionDeg.isNotEmpty ? node.directionDeg.first : 0, // Direction not used for deletions but required for API
      profile: null, // No profile needed for deletions - just delete by node ID
      uploadMode: uploadMode,
      operation: UploadOperation.delete,
      originalNodeId: node.id,
    );
    
    _queue.add(upload);
    _saveQueue();
    
    // Mark the original node as pending deletion in the cache
    final deletionTags = Map<String, String>.from(node.tags);
    deletionTags['_pending_deletion'] = 'true';
    
    final nodeWithDeletionTag = OsmNode(
      id: node.id,
      coord: node.coord,
      tags: deletionTags,
    );
    
    NodeCache.instance.addOrUpdate([nodeWithDeletionTag]);
    // Notify node provider to update the map
    NodeProviderWithCache.instance.notifyListeners();
    
    notifyListeners();
  }

  void clearQueue() {
    // Clean up all pending nodes from cache before clearing queue
    for (final upload in _queue) {
      _cleanupPendingNodeFromCache(upload);
    }
    
    _queue.clear();
    _saveQueue();
    
    // Notify node provider to update the map
    NodeProviderWithCache.instance.notifyListeners();
    notifyListeners();
  }
  
  void removeFromQueue(PendingUpload upload) {
    // Clean up pending node from cache before removing from queue
    _cleanupPendingNodeFromCache(upload);
    
    _queue.remove(upload);
    _saveQueue();
    
    // Notify node provider to update the map
    NodeProviderWithCache.instance.notifyListeners();
    notifyListeners();
  }

  void retryUpload(PendingUpload upload) {
    upload.clearError();
    upload.attempts = 0;
    _saveQueue();
    notifyListeners();
  }

  // Start the upload processing loop
  void startUploader({
    required bool offlineMode, 
    required bool pauseQueueProcessing,
    required UploadMode uploadMode,
    required Future<String?> Function() getAccessToken,
  }) {
    _uploadTimer?.cancel();

    // No uploads if queue is empty, offline mode is enabled, or queue processing is paused
    if (_queue.isEmpty || offlineMode || pauseQueueProcessing) return;

    _uploadTimer = Timer.periodic(const Duration(seconds: 10), (t) async {
      if (_queue.isEmpty || offlineMode || pauseQueueProcessing) {
        _uploadTimer?.cancel();
        return;
      }

      // Find next item to process based on state
      final pendingItems = _queue.where((pu) => pu.uploadState == UploadState.pending).toList();
      final creatingChangesetItems = _queue.where((pu) => pu.uploadState == UploadState.creatingChangeset).toList();
      final uploadingItems = _queue.where((pu) => pu.uploadState == UploadState.uploading).toList();
      final closingItems = _queue.where((pu) => pu.uploadState == UploadState.closingChangeset).toList();
      
      // Process any expired items
      for (final uploadingItem in uploadingItems) {
        if (uploadingItem.hasChangesetExpired) {
          debugPrint('[UploadQueue] Changeset expired during node submission - marking as failed');
          uploadingItem.setError('Could not submit node within 59 minutes - changeset expired');
          _saveQueue();
          notifyListeners();
        }
      }
      
      for (final closingItem in closingItems) {
        if (closingItem.hasChangesetExpired) {
          debugPrint('[UploadQueue] Changeset expired during close - trusting OSM auto-close (node was submitted successfully)');
          _markAsCompleting(closingItem, submittedNodeId: closingItem.submittedNodeId!);
          // Continue processing loop - don't return here
        }
      }
      
      // Find next item to process (process in stage order)
      PendingUpload? item;
      if (pendingItems.isNotEmpty) {
        item = pendingItems.first;
      } else if (creatingChangesetItems.isNotEmpty) {
        // Already in progress, skip
        return;
      } else if (uploadingItems.isNotEmpty) {
        // Check if any uploading items are ready for retry
        final readyToRetry = uploadingItems.where((ui) => 
          !ui.hasChangesetExpired && ui.isReadyForNodeSubmissionRetry
        ).toList();
        
        if (readyToRetry.isNotEmpty) {
          item = readyToRetry.first;
        }
      } else {
        // No active items, check if any changeset close items are ready for retry
        final readyToRetry = closingItems.where((ci) => 
          !ci.hasChangesetExpired && ci.isReadyForChangesetCloseRetry
        ).toList();
        
        if (readyToRetry.isNotEmpty) {
          item = readyToRetry.first;
        }
      }
      
      if (item == null) {
        // No items ready for processing - check if queue is effectively empty
        final hasActiveItems = _queue.any((pu) => 
          pu.uploadState == UploadState.pending || 
          pu.uploadState == UploadState.creatingChangeset ||
          (pu.uploadState == UploadState.uploading && !pu.hasChangesetExpired) ||
          (pu.uploadState == UploadState.closingChangeset && !pu.hasChangesetExpired)
        );
        
        if (!hasActiveItems) {
          debugPrint('[UploadQueue] No active items remaining, stopping uploader');
          _uploadTimer?.cancel();
        }
        return; // Nothing to process right now
      }

      // Retrieve access after every tick (accounts for re-login)
      final access = await getAccessToken();
      if (access == null) return; // not logged in

      debugPrint('[UploadQueue] Processing item in state: ${item.uploadState} with uploadMode: ${item.uploadMode}');
      
      if (item.uploadState == UploadState.pending) {
        await _processCreateChangeset(item, access);
      } else if (item.uploadState == UploadState.creatingChangeset) {
        // Already in progress, skip (shouldn't happen due to filtering above)
        debugPrint('[UploadQueue] Changeset creation already in progress, skipping');
        return;
      } else if (item.uploadState == UploadState.uploading) {
        await _processNodeOperation(item, access);
      } else if (item.uploadState == UploadState.closingChangeset) {
        await _processChangesetClose(item, access);
      }
    });
  }

  // Process changeset creation (step 1 of 3)
  Future<void> _processCreateChangeset(PendingUpload item, String access) async {
    item.markAsCreatingChangeset();
    _saveQueue();
    notifyListeners(); // Show "Creating changeset..." immediately
    
    if (item.uploadMode == UploadMode.simulate) {
      // Simulate successful upload without calling real API
      debugPrint('[UploadQueue] Simulating changeset creation (no real API call)');
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
      
      // Move to node operation phase
      item.markChangesetCreated('simulate-changeset-${DateTime.now().millisecondsSinceEpoch}');
      _saveQueue();
      notifyListeners();
      return;
    }
    
    // Real changeset creation
    debugPrint('[UploadQueue] Creating changeset for ${item.operation.name} operation');
    final up = Uploader(access, (nodeId) {}, (errorMessage) {}, uploadMode: item.uploadMode);
    final result = await up.createChangeset(item);
    
    if (result.success) {
      // Changeset created successfully - move to node operation phase
      debugPrint('[UploadQueue] Changeset ${result.changesetId} created successfully');
      item.markChangesetCreated(result.changesetId!);
      _saveQueue();
      notifyListeners(); // Show "Uploading node..." next
    } else {
      // Changeset creation failed
      item.attempts++;
      _saveQueue();
      notifyListeners(); // Show attempt count immediately
      
      if (item.attempts >= 3) {
        item.setError(result.errorMessage ?? 'Changeset creation failed after 3 attempts');
        _saveQueue();
        notifyListeners(); // Show error state immediately
      } else {
        // Reset to pending for retry
        item.uploadState = UploadState.pending;
        _saveQueue();
        notifyListeners(); // Show pending state for retry
        await Future.delayed(const Duration(seconds: 20));
      }
    }
  }

  // Process node operation (step 2 of 3)
  Future<void> _processNodeOperation(PendingUpload item, String access) async {
    if (item.changesetId == null) {
      debugPrint('[UploadQueue] ERROR: No changeset ID for node operation');
      item.setError('Missing changeset ID for node operation');
      _saveQueue();
      notifyListeners();
      return;
    }

    // Check if 59-minute window has expired
    if (item.hasChangesetExpired) {
      debugPrint('[UploadQueue] Changeset expired, could not submit node within 59 minutes');
      item.setError('Could not submit node within 59 minutes - changeset expired');
      _saveQueue();
      notifyListeners();
      return;
    }
    
    debugPrint('[UploadQueue] Processing node operation with changeset ${item.changesetId} (attempt ${item.nodeSubmissionAttempts + 1})');
    
    if (item.uploadMode == UploadMode.simulate) {
      // Simulate successful node operation without calling real API
      debugPrint('[UploadQueue] Simulating node operation (no real API call)');
      await Future.delayed(const Duration(milliseconds: 500)); // Simulate network delay
      
      // Store simulated node ID and move to changeset close phase
      item.submittedNodeId = DateTime.now().millisecondsSinceEpoch;
      item.markNodeOperationComplete();
      _saveQueue();
      notifyListeners();
      return;
    }
    
    // Real node operation
    final up = Uploader(access, (nodeId) {
      // This callback is called when node operation succeeds
      item.submittedNodeId = nodeId;
    }, (errorMessage) {
      // Error handling is done below
    }, uploadMode: item.uploadMode);
    
    final result = await up.performNodeOperation(item, item.changesetId!);
    
    item.incrementNodeSubmissionAttempts(); // Record this attempt
    _saveQueue();
    notifyListeners(); // Show attempt count immediately
    
    if (result.success) {
      // Node operation succeeded - move to changeset close phase
      debugPrint('[UploadQueue] Node operation succeeded after ${item.nodeSubmissionAttempts} attempts, node ID: ${result.nodeId}');
      item.submittedNodeId = result.nodeId;
      item.markNodeOperationComplete();
      _saveQueue();
      notifyListeners(); // Show "Closing changeset..." next
    } else {
      // Node operation failed - will retry within 59-minute window
      debugPrint('[UploadQueue] Node operation failed (attempt ${item.nodeSubmissionAttempts}): ${result.errorMessage}');
      
      // Check if we have time for another retry
      if (item.hasChangesetExpired) {
        debugPrint('[UploadQueue] Changeset expired during retry, marking as failed');
        item.setError('Could not submit node within 59 minutes - ${result.errorMessage}');
        _saveQueue();
        notifyListeners();
      } else {
        // Still have time, will retry after backoff delay
        final nextDelay = item.nextNodeSubmissionRetryDelay;
        final timeLeft = item.timeUntilAutoClose;
        debugPrint('[UploadQueue] Will retry node submission in ${nextDelay}, ${timeLeft?.inMinutes}m remaining');
        // No state change needed - attempt count was already updated above
      }
    }
  }

  // Process changeset close operation (step 3 of 3)
  Future<void> _processChangesetClose(PendingUpload item, String access) async {
    if (item.changesetId == null) {
      debugPrint('[UploadQueue] ERROR: No changeset ID for closing');
      item.setError('Missing changeset ID');
      _saveQueue();
      notifyListeners();
      return;
    }

    // Check if 59-minute window has expired - if so, mark as complete (trust OSM auto-close)
    if (item.hasChangesetExpired) {
      debugPrint('[UploadQueue] Changeset expired - trusting OSM auto-close (node was submitted successfully)');
      _markAsCompleting(item, submittedNodeId: item.submittedNodeId!);
      return;
    }
    
    debugPrint('[UploadQueue] Attempting to close changeset ${item.changesetId} (attempt ${item.changesetCloseAttempts + 1})');
    
    if (item.uploadMode == UploadMode.simulate) {
      // Simulate successful changeset close without calling real API
      debugPrint('[UploadQueue] Simulating changeset close (no real API call)');
      await Future.delayed(const Duration(milliseconds: 300)); // Simulate network delay
      
      // Mark as complete
      _markAsCompleting(item, submittedNodeId: item.submittedNodeId!);
      return;
    }
    
    // Real changeset close
    final up = Uploader(access, (nodeId) {}, (errorMessage) {}, uploadMode: item.uploadMode);
    final result = await up.closeChangeset(item.changesetId!);
    
    item.incrementChangesetCloseAttempts(); // This records the attempt time
    _saveQueue();
    notifyListeners(); // Show attempt count immediately
    
    if (result.success) {
      // Changeset closed successfully
      debugPrint('[UploadQueue] Changeset close succeeded after ${item.changesetCloseAttempts} attempts');
      _markAsCompleting(item, submittedNodeId: item.submittedNodeId!);
      // _markAsCompleting handles its own save/notify
    } else if (result.changesetNotFound) {
      // Changeset not found - this suggests the upload may not have worked, start over with full retry  
      debugPrint('[UploadQueue] Changeset not found during close, marking for full retry');
      item.setError(result.errorMessage ?? 'Changeset not found');
      _saveQueue();
      notifyListeners(); // Show error state immediately
    } else {
      // Changeset close failed - will retry after exponential backoff delay
      // Note: This will NEVER error out - will keep trying until 59-minute window expires
      final nextDelay = item.nextChangesetCloseRetryDelay;
      final timeLeft = item.timeUntilAutoClose;
      debugPrint('[UploadQueue] Changeset close failed (attempt ${item.changesetCloseAttempts}), will retry in ${nextDelay}, ${timeLeft?.inMinutes}m remaining');
      debugPrint('[UploadQueue] Error: ${result.errorMessage}');
      // No additional state change needed - attempt count was already updated above
    }
  }

  void stopUploader() {
    _uploadTimer?.cancel();
  }

  // Mark an item as completing (shows checkmark) and schedule removal after 1 second
  void _markAsCompleting(PendingUpload item, {int? submittedNodeId, int? simulatedNodeId}) {
    item.markAsComplete();
    
    // Store the submitted node ID for cleanup purposes
    if (submittedNodeId != null) {
      item.submittedNodeId = submittedNodeId;
      
      if (item.isDeletion) {
        debugPrint('[UploadQueue] Deletion successful, removing node ID: $submittedNodeId from cache');
        _handleSuccessfulDeletion(item);
      } else {
        debugPrint('[UploadQueue] Upload successful, OSM assigned node ID: $submittedNodeId');
        // Update cache with real node ID instead of temp ID
        _updateCacheWithRealNodeId(item, submittedNodeId);
      }
    } else if (simulatedNodeId != null && item.uploadMode == UploadMode.simulate) {
      // For simulate mode, use a fake but positive ID 
      item.submittedNodeId = simulatedNodeId;
      if (item.isDeletion) {
        debugPrint('[UploadQueue] Simulated deletion, removing fake node ID: $simulatedNodeId from cache');
        _handleSuccessfulDeletion(item);
      } else {
        debugPrint('[UploadQueue] Simulated upload, fake node ID: $simulatedNodeId');
      }
    }
    
    _saveQueue();
    notifyListeners();
    
    // Remove the item after 1 second
    Timer(const Duration(seconds: 1), () {
      _queue.remove(item);
      _saveQueue();
      notifyListeners();
    });
  }
  
  // Update the cache to use the real OSM node ID instead of temporary ID
  void _updateCacheWithRealNodeId(PendingUpload item, int realNodeId) {
    // Create the node with real ID and clean tags (remove temp markers)
    final tags = item.getCombinedTags();
    
    final realNode = OsmNode(
      id: realNodeId,
      coord: item.coord,
      tags: tags, // Clean tags without _pending_upload markers
    );
    
    // Add/update the cache with the real node
    NodeCache.instance.addOrUpdate([realNode]);
    
    // Clean up the specific temp node for this upload
    if (item.tempNodeId != null) {
      NodeCache.instance.removeTempNodeById(item.tempNodeId!);
    }
    
    // For modify operations, clean up the original node's _pending_edit marker
    // For extract operations, we don't modify the original node so leave it unchanged
    if (item.isEdit && item.originalNodeId != null) {
      // Remove the _pending_edit marker from the original node in cache
      // The next Overpass fetch will provide the authoritative data anyway
      NodeCache.instance.removePendingEditMarker(item.originalNodeId!);
    }
    
    // Notify node provider to update the map
    NodeProviderWithCache.instance.notifyListeners();
  }

  // Handle successful deletion by removing the node from cache
  void _handleSuccessfulDeletion(PendingUpload item) {
    if (item.originalNodeId != null) {
      // Remove the node from cache entirely
      NodeCache.instance.removeNodeById(item.originalNodeId!);
      
      // Notify node provider to update the map
      NodeProviderWithCache.instance.notifyListeners();
    }
  }

  // Helper method to format multiple directions for submission, supporting profile FOV
  dynamic _formatDirectionsForSubmission(List<double> directions, NodeProfile? profile) {
    if (directions.isEmpty) return 0.0;
    
    // If profile has FOV, convert center directions to range notation
    if (profile?.fov != null && profile!.fov! > 0) {
      final ranges = directions.map((center) => 
        _formatDirectionWithFov(center, profile.fov!)
      ).toList();
      
      return ranges.length == 1 ? ranges.first : ranges.join(';');
    }
    
    // No profile FOV: use original format (single number or semicolon-separated)
    if (directions.length == 1) return directions.first;
    return directions.map((d) => d.round().toString()).join(';');
  }

  // Convert a center direction and FOV to range notation (e.g., 180° center with 90° FOV -> "135-225")
  String _formatDirectionWithFov(double center, double fov) {
    final halfFov = fov / 2;
    final start = (center - halfFov + 360) % 360;
    final end = (center + halfFov) % 360;
    
    return '${start.round()}-${end.round()}';
  }

  // Clean up pending nodes from cache when queue items are deleted/cleared
  void _cleanupPendingNodeFromCache(PendingUpload upload) {
    if (upload.isDeletion) {
      // For deletions: remove the _pending_deletion marker from the original node
      if (upload.originalNodeId != null) {
        NodeCache.instance.removePendingDeletionMarker(upload.originalNodeId!);
      }
    } else if (upload.isEdit) {
      // For edits: remove the specific temp node and the _pending_edit marker from original
      if (upload.tempNodeId != null) {
        NodeCache.instance.removeTempNodeById(upload.tempNodeId!);
      }
      if (upload.originalNodeId != null) {
        NodeCache.instance.removePendingEditMarker(upload.originalNodeId!);
      }
    } else if (upload.operation == UploadOperation.extract) {
      // For extracts: remove the specific temp node (leave original unchanged)
      if (upload.tempNodeId != null) {
        NodeCache.instance.removeTempNodeById(upload.tempNodeId!);
      }
    } else {
      // For creates: remove the specific temp node
      if (upload.tempNodeId != null) {
        NodeCache.instance.removeTempNodeById(upload.tempNodeId!);
      }
    }
  }

  // ---------- Queue persistence ----------
  Future<void> _saveQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _queue.map((e) => e.toJson()).toList();
    await prefs.setString('queue', jsonEncode(jsonList));
  }

  Future<void> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('queue');
    if (jsonStr == null) return;
    final list = jsonDecode(jsonStr) as List<dynamic>;
    _queue
      ..clear()
      ..addAll(list.map((e) => PendingUpload.fromJson(e)));
  }

  // Public method for migration purposes
  Future<void> reloadQueue() async {
    await _loadQueue();
    notifyListeners();
  }

  // Public method to manually trigger cache repopulation (useful for debugging or after cache clears)
  void repopulateCacheFromQueue() {
    _repopulateCacheFromQueue();
  }

  @override
  void dispose() {
    _uploadTimer?.cancel();
    super.dispose();
  }
}
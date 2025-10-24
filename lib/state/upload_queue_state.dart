import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pending_upload.dart';
import '../models/osm_node.dart';
import '../models/node_profile.dart';
import '../services/node_cache.dart';
import '../services/uploader.dart';
import '../widgets/camera_provider_with_cache.dart';
import 'settings_state.dart';
import 'session_state.dart';

class UploadQueueState extends ChangeNotifier {
  final List<PendingUpload> _queue = [];
  Timer? _uploadTimer;

  // Getters
  int get pendingCount => _queue.length;
  List<PendingUpload> get pendingUploads => List.unmodifiable(_queue);

  // Initialize by loading queue from storage
  Future<void> init() async {
    await _loadQueue();
  }

  // Add a completed session to the upload queue
  void addFromSession(AddNodeSession session, {required UploadMode uploadMode}) {
    final upload = PendingUpload(
      coord: session.target!,
      direction: session.directionDegrees,
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
    
    final tempNode = OsmNode(
      id: tempId,
      coord: upload.coord,
      tags: tags,
    );
    
    NodeCache.instance.addOrUpdate([tempNode]);
    // Notify node provider to update the map
    CameraProviderWithCache.instance.notifyListeners();
    
    notifyListeners();
  }

  // Add a completed edit session to the upload queue
  void addFromEditSession(EditNodeSession session, {required UploadMode uploadMode}) {
    final upload = PendingUpload(
      coord: session.target,
      direction: session.directionDegrees,
      profile: session.profile!,  // Safe to use ! because commitEditSession() checks for null
      operatorProfile: session.operatorProfile,
      uploadMode: uploadMode,
      operation: UploadOperation.modify,
      originalNodeId: session.originalNode.id, // Track which node we're editing
    );
    
    _queue.add(upload);
    _saveQueue();
    
    // Create two cache entries:
    
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
    
    final editedNode = OsmNode(
      id: tempId,
      coord: upload.coord, // At new location
      tags: editedTags,
    );
    
    NodeCache.instance.addOrUpdate([originalNode, editedNode]);
    // Notify node provider to update the map
    CameraProviderWithCache.instance.notifyListeners();
    
    notifyListeners();
  }

  // Add a node deletion to the upload queue
  void addFromNodeDeletion(OsmNode node, {required UploadMode uploadMode}) {
    final upload = PendingUpload(
      coord: node.coord,
      direction: node.directionDeg ?? 0, // Use existing direction or default to 0
      profile: NodeProfile.genericAlpr(), // Dummy profile - not used for deletions
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
    CameraProviderWithCache.instance.notifyListeners();
    
    notifyListeners();
  }

  void clearQueue() {
    _queue.clear();
    _saveQueue();
    notifyListeners();
  }
  
  void removeFromQueue(PendingUpload upload) {
    _queue.remove(upload);
    _saveQueue();
    notifyListeners();
  }

  void retryUpload(PendingUpload upload) {
    upload.error = false;
    upload.attempts = 0;
    _saveQueue();
    notifyListeners();
  }

  // Start the upload processing loop
  void startUploader({
    required bool offlineMode, 
    required UploadMode uploadMode,
    required Future<String?> Function() getAccessToken,
  }) {
    _uploadTimer?.cancel();

    // No uploads without queue, or if offline mode is enabled.
    if (_queue.isEmpty || offlineMode) return;

    _uploadTimer = Timer.periodic(const Duration(seconds: 10), (t) async {
      if (_queue.isEmpty || offlineMode) {
        _uploadTimer?.cancel();
        return;
      }

      // Find the first queue item that is NOT in error state and act on that
      final item = _queue.where((pu) => !pu.error).cast<PendingUpload?>().firstOrNull;
      if (item == null) return;

      // Retrieve access after every tick (accounts for re-login)
      final access = await getAccessToken();
      if (access == null) return; // not logged in

      bool ok;
      debugPrint('[UploadQueue] Processing item with uploadMode: ${item.uploadMode}');
      if (item.uploadMode == UploadMode.simulate) {
        // Simulate successful upload without calling real API
        debugPrint('[UploadQueue] Simulating upload (no real API call)');
        await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
        ok = true;
        // Simulate a node ID for simulate mode
        _markAsCompleting(item, simulatedNodeId: DateTime.now().millisecondsSinceEpoch);
      } else {
        // Real upload -- use the upload mode that was saved when this item was queued
        debugPrint('[UploadQueue] Real upload to: ${item.uploadMode}');
        final up = Uploader(access, (nodeId) {
          _markAsCompleting(item, submittedNodeId: nodeId);
        }, uploadMode: item.uploadMode);
        ok = await up.upload(item);
      }
      if (!ok) {
        item.attempts++;
        if (item.attempts >= 3) {
          // Mark as error and stop the uploader. User can manually retry.
          item.error = true;
          _saveQueue();
          notifyListeners();
          _uploadTimer?.cancel();
        } else {
          await Future.delayed(const Duration(seconds: 20));
        }
      }
    });
  }

  void stopUploader() {
    _uploadTimer?.cancel();
  }

  // Mark an item as completing (shows checkmark) and schedule removal after 1 second
  void _markAsCompleting(PendingUpload item, {int? submittedNodeId, int? simulatedNodeId}) {
    item.completing = true;
    
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
    
    // Clean up any temp nodes at the same coordinate
    NodeCache.instance.removeTempNodesByCoordinate(item.coord);
    
    // For edits, also clean up the original node's _pending_edit marker
    if (item.isEdit && item.originalNodeId != null) {
      // Remove the _pending_edit marker from the original node in cache
      // The next Overpass fetch will provide the authoritative data anyway
      NodeCache.instance.removePendingEditMarker(item.originalNodeId!);
    }
    
    // Notify node provider to update the map
    CameraProviderWithCache.instance.notifyListeners();
  }

  // Handle successful deletion by removing the node from cache
  void _handleSuccessfulDeletion(PendingUpload item) {
    if (item.originalNodeId != null) {
      // Remove the node from cache entirely
      NodeCache.instance.removeNodeById(item.originalNodeId!);
      
      // Notify node provider to update the map
      CameraProviderWithCache.instance.notifyListeners();
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

  @override
  void dispose() {
    _uploadTimer?.cancel();
    super.dispose();
  }
}
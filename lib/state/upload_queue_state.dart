import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pending_upload.dart';
import '../models/osm_camera_node.dart';
import '../services/camera_cache.dart';
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
  void addFromSession(AddCameraSession session, {required UploadMode uploadMode}) {
    final upload = PendingUpload(
      coord: session.target!,
      direction: session.directionDegrees,
      profile: session.profile,
      uploadMode: uploadMode,
    );
    
    _queue.add(upload);
    _saveQueue();
    
    // Add to camera cache immediately so it shows on the map
    // Create a temporary node with a negative ID (to distinguish from real OSM nodes)
    // Using timestamp as negative ID to ensure uniqueness
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final tags = Map<String, String>.from(upload.profile.tags);
    tags['direction'] = upload.direction.toStringAsFixed(0);
    tags['_pending_upload'] = 'true'; // Mark as pending for potential UI distinction
    
    final tempNode = OsmCameraNode(
      id: tempId,
      coord: upload.coord,
      tags: tags,
    );
    
    CameraCache.instance.addOrUpdate([tempNode]);
    // Notify camera provider to update the map
    CameraProviderWithCache.instance.notifyListeners();
    
    notifyListeners();
  }

  // Add a completed edit session to the upload queue
  void addFromEditSession(EditCameraSession session, {required UploadMode uploadMode}) {
    final upload = PendingUpload(
      coord: session.target,
      direction: session.directionDegrees,
      profile: session.profile,
      uploadMode: uploadMode,
      originalNodeId: session.originalNode.id, // Track which node we're editing
    );
    
    _queue.add(upload);
    _saveQueue();
    
    // Create two cache entries:
    
    // 1. Mark the original camera with _pending_edit (grey ring) at original location
    final originalTags = Map<String, String>.from(session.originalNode.tags);
    originalTags['_pending_edit'] = 'true'; // Mark original as having pending edit
    
    final originalNode = OsmCameraNode(
      id: session.originalNode.id,
      coord: session.originalNode.coord, // Keep at original location
      tags: originalTags,
    );
    
    // 2. Create new temp node for the edited camera (purple ring) at new location
    final tempId = -DateTime.now().millisecondsSinceEpoch;
    final editedTags = Map<String, String>.from(upload.profile.tags);
    editedTags['direction'] = upload.direction.toStringAsFixed(0);
    editedTags['_pending_upload'] = 'true'; // Mark as pending upload
    editedTags['_original_node_id'] = session.originalNode.id.toString(); // Track original for line drawing
    
    final editedNode = OsmCameraNode(
      id: tempId,
      coord: upload.coord, // At new location
      tags: editedTags,
    );
    
    CameraCache.instance.addOrUpdate([originalNode, editedNode]);
    // Notify camera provider to update the map
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
      } else {
        // Real upload -- use the upload mode that was saved when this item was queued
        debugPrint('[UploadQueue] Real upload to: ${item.uploadMode}');
        final up = Uploader(access, () {
          _markAsCompleting(item);
        }, uploadMode: item.uploadMode);
        ok = await up.upload(item);
      }

      if (ok && item.uploadMode == UploadMode.simulate) {
        // Mark as completing for simulate mode too
        _markAsCompleting(item);
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
  void _markAsCompleting(PendingUpload item) {
    item.completing = true;
    _saveQueue();
    notifyListeners();
    
    // Remove the item after 1 second
    Timer(const Duration(seconds: 1), () {
      _queue.remove(item);
      _saveQueue();
      notifyListeners();
    });
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
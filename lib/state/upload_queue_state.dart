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
  void addFromSession(AddCameraSession session) {
    final upload = PendingUpload(
      coord: session.target!,
      direction: session.directionDegrees,
      profile: session.profile,
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
      if (uploadMode == UploadMode.simulate) {
        // Simulate successful upload without calling real API
        await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
        ok = true;
      } else {
        // Real upload -- pass uploadMode so uploader can switch between prod and sandbox
        final up = Uploader(access, () {
          _queue.remove(item);
          _saveQueue();
          notifyListeners();
        }, uploadMode: uploadMode);
        ok = await up.upload(item);
      }

      if (ok && uploadMode == UploadMode.simulate) {
        // Remove manually for simulate mode
        _queue.remove(item);
        _saveQueue();
        notifyListeners();
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
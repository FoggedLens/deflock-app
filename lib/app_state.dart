import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/camera_profile.dart';
import 'models/pending_upload.dart';
import 'services/auth_service.dart';
import 'services/uploader.dart';
import 'services/profile_service.dart';

// ------------------ AddCameraSession ------------------
class AddCameraSession {
  AddCameraSession({required this.profile, this.directionDegrees = 0});
  CameraProfile profile;
  double directionDegrees;
  LatLng? target;
}

// ------------------ AppState ------------------
class AppState extends ChangeNotifier {
  AppState() {
    _init();
  }

  final _auth = AuthService();
  String? _username;

  final List<CameraProfile> _profiles = [];
  final Set<CameraProfile> _enabled = {};
  
  // Test mode - prevents actual uploads to OSM
  bool _testMode = false;
  bool get testMode => _testMode;
  void setTestMode(bool enabled) {
    _testMode = enabled;
    print('AppState: Test mode ${enabled ? 'enabled' : 'disabled'}');
    notifyListeners();
  }

  AddCameraSession? _session;
  AddCameraSession? get session => _session;

  final List<PendingUpload> _queue = [];
  Timer? _uploadTimer;

  bool get isLoggedIn => _username != null;
  String get username => _username ?? '';

  // ---------- Init ----------
  Future<void> _init() async {
    // Initialize profiles: built-in + custom
    _profiles.add(CameraProfile.alpr());
    _profiles.addAll(await ProfileService().load());
    _enabled.addAll(_profiles);

    await _loadQueue();
    
    // Check if we're already logged in and get username
    try {
      if (await _auth.isLoggedIn()) {
        print('AppState: User appears to be logged in, fetching username...');
        _username = await _auth.login();
        if (_username != null) {
          print('AppState: Successfully retrieved username: $_username');
        } else {
          print('AppState: Failed to retrieve username despite being logged in');
        }
      } else {
        print('AppState: User is not logged in');
      }
    } catch (e) {
      print('AppState: Error during auth initialization: $e');
    }
    
    _startUploader();
    notifyListeners();
  }

  // ---------- Auth ----------
  Future<void> login() async {
    try {
      print('AppState: Starting login process...');
      _username = await _auth.login();
      if (_username != null) {
        print('AppState: Login successful for user: $_username');
      } else {
        print('AppState: Login failed - no username returned');
      }
    } catch (e) {
      print('AppState: Login error: $e');
      _username = null;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.logout();
    _username = null;
    notifyListeners();
  }

  // Add method to refresh auth state
  Future<void> refreshAuthState() async {
    try {
      print('AppState: Refreshing auth state...');
      if (await _auth.isLoggedIn()) {
        print('AppState: Token exists, fetching username...');
        _username = await _auth.login();
        if (_username != null) {
          print('AppState: Auth refresh successful: $_username');
        } else {
          print('AppState: Auth refresh failed - no username');
        }
      } else {
        print('AppState: No valid token found');
        _username = null;
      }
    } catch (e) {
      print('AppState: Auth refresh error: $e');
      _username = null;
    }
    notifyListeners();
  }

  // Force a completely fresh login (clears stored tokens)
  Future<void> forceLogin() async {
    try {
      print('AppState: Starting forced fresh login...');
      _username = await _auth.forceLogin();
      if (_username != null) {
        print('AppState: Forced login successful: $_username');
      } else {
        print('AppState: Forced login failed - no username returned');
      }
    } catch (e) {
      print('AppState: Forced login error: $e');
      _username = null;
    }
    notifyListeners();
  }

  // Validate current token/credentials
  Future<bool> validateToken() async {
    try {
      return await _auth.isLoggedIn();
    } catch (e) {
      print('AppState: Token validation error: $e');
      return false;
    }
  }

  // ---------- Profiles ----------
  List<CameraProfile> get profiles => List.unmodifiable(_profiles);
  bool isEnabled(CameraProfile p) => _enabled.contains(p);
  List<CameraProfile> get enabledProfiles =>
      _profiles.where(isEnabled).toList(growable: false);
  void toggleProfile(CameraProfile p, bool e) {
    e ? _enabled.add(p) : _enabled.remove(p);
    notifyListeners();
  }

  void addOrUpdateProfile(CameraProfile p) {
    final idx = _profiles.indexWhere((x) => x.id == p.id);
    if (idx >= 0) {
      _profiles[idx] = p;
    } else {
      _profiles.add(p);
      _enabled.add(p);
    }
    ProfileService().save(_profiles);
    notifyListeners();
  }

  void deleteProfile(CameraProfile p) {
    if (p.builtin) return;
    _enabled.remove(p);
    _profiles.removeWhere((x) => x.id == p.id);
    ProfileService().save(_profiles);
    notifyListeners();
  }

  // ---------- Add‑camera session ----------
  void startAddSession() {
    _session = AddCameraSession(profile: enabledProfiles.first);
    notifyListeners();
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
    if (dirty) notifyListeners();   // <-- slider & map update
  }

  void cancelSession() {
    _session = null;
    notifyListeners();
  }

  void commitSession() {
    if (_session?.target == null) return;
    _queue.add(
      PendingUpload(
        coord: _session!.target!,
        direction: _session!.directionDegrees,
        profile: _session!.profile,
      ),
    );
    _saveQueue();
    _session = null;
    
    // Restart uploader when new items are added
    _startUploader();
    
    notifyListeners();
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

  // ---------- Uploader ----------
  void _startUploader() {
    _uploadTimer?.cancel();

    // No uploads without auth or queue.
    if (_queue.isEmpty) return;

    _uploadTimer = Timer.periodic(const Duration(seconds: 10), (t) async {
      if (_queue.isEmpty) return;

      final access = await _auth.getAccessToken();
      if (access == null) return; // not logged in

      final item = _queue.first;
      
      bool ok;
      if (_testMode) {
        // Test mode - simulate successful upload without actually calling OSM API
        print('AppState: Test mode - simulating upload for ${item.coord}');
        await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
        ok = true;
        print('AppState: Test mode - simulated upload successful');
      } else {
        // Real upload
        final up = Uploader(access, () {
          _queue.remove(item);
          _saveQueue();
          notifyListeners();
        });
        ok = await up.upload(item);
      }
      
      if (ok && _testMode) {
        // In test mode, manually remove from queue since Uploader callback won't be called
        _queue.remove(item);
        _saveQueue();
        notifyListeners();
      }
      if (!ok) {
        item.attempts++;
        if (item.attempts >= 3) {
          // give up until next launch
          _uploadTimer?.cancel();
        } else {
          await Future.delayed(const Duration(seconds: 20));
        }
      }
    });
  }

  // ---------- Exposed getters ----------
  int get pendingCount => _queue.length;
  List<PendingUpload> get pendingUploads => List.unmodifiable(_queue);
  
  // ---------- Queue management ----------
  void clearQueue() {
    print('AppState: Clearing upload queue (${_queue.length} items)');
    _queue.clear();
    _saveQueue();
    notifyListeners();
  }
  
  void removeFromQueue(PendingUpload upload) {
    print('AppState: Removing upload from queue: ${upload.coord}');
    _queue.remove(upload);
    _saveQueue();
    notifyListeners();
  }
}

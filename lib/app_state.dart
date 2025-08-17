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
import 'widgets/tile_provider_with_cache.dart';

// Enum for upload mode (Production, OSM Sandbox, Simulate)
enum UploadMode { production, sandbox, simulate }

// ------------------ AddCameraSession ------------------
class AddCameraSession {
  AddCameraSession({required this.profile, this.directionDegrees = 0});
  CameraProfile profile;
  double directionDegrees;
  LatLng? target;
}


// ------------------ AppState ------------------
class AppState extends ChangeNotifier {
  static late AppState instance;
  AppState() {
    instance = this;
    _init();
  }

  // ------------------- Offline Mode -------------------
  static const String _offlineModePrefsKey = 'offline_mode';
  bool _offlineMode = false;
  bool get offlineMode => _offlineMode;
  Future<void> setOfflineMode(bool enabled) async {
    final wasOffline = _offlineMode;
    _offlineMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineModePrefsKey, enabled);
    if (wasOffline && !enabled) {
      // Transitioning from offline to online: clear tile cache!
      TileProviderWithCache.clearCache();
      _startUploader(); // Resume upload queue processing as we leave offline mode
    }
    notifyListeners();
  }

  final _auth = AuthService();
  String? _username;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  final List<CameraProfile> _profiles = [];
  final Set<CameraProfile> _enabled = {};
  static const String _enabledPrefsKey = 'enabled_profiles';
  static const String _maxCamerasPrefsKey = 'max_cameras';

  // Maximum number of cameras fetched/drawn
  int _maxCameras = 250;
  int get maxCameras => _maxCameras;
  set maxCameras(int n) {
    if (n < 10) n = 10; // minimum
    _maxCameras = n;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_maxCamerasPrefsKey, n);
    });
    notifyListeners();
  }

  // Upload mode: production, sandbox, or simulate (in-memory, no uploads)
  UploadMode _uploadMode = UploadMode.simulate;
  static const String _uploadModePrefsKey = 'upload_mode';
  UploadMode get uploadMode => _uploadMode;
  Future<void> setUploadMode(UploadMode mode) async {
    _uploadMode = mode;
    // Update AuthService to match new mode
    _auth.setUploadMode(mode);
    // Refresh user display for active mode, validating token
    try {
      if (await _auth.isLoggedIn()) {
        print('AppState: Switching mode, token exists; validating...');
        final isValid = await validateToken();
        if (isValid) {
          print("AppState: Switching mode; fetching username for $mode...");
          _username = await _auth.login();
          if (_username != null) {
            print("AppState: Switched mode, now logged in as $_username");
          } else {
            print('AppState: Switched mode but failed to retrieve username');
          }
        } else {
          print('AppState: Switching mode, token invalid—auto-logout.');
          await logout(); // This clears _username also.
        }
      } else {
        _username = null;
        print("AppState: Mode change: not logged in in $mode");
      }
    } catch (e) {
      _username = null;
      print("AppState: Mode change user restoration error: $e");
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_uploadModePrefsKey, mode.index);
    print("AppState: Upload mode set to $mode");
    notifyListeners();
  }

  // For legacy bool test mode
  static const String _legacyTestModePrefsKey = 'test_mode';

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

    // Load enabled profile IDs and upload/test mode from prefs
    final prefs = await SharedPreferences.getInstance();
    final enabledIds = prefs.getStringList(_enabledPrefsKey);
    if (enabledIds != null && enabledIds.isNotEmpty) {
      // Restore enabled profiles by id
      _enabled.addAll(_profiles.where((p) => enabledIds.contains(p.id)));
    } else {
      // By default, all are enabled
      _enabled.addAll(_profiles);
    }
    // Upload mode loading (including migration from old test_mode bool)
    if (prefs.containsKey(_uploadModePrefsKey)) {
      final idx = prefs.getInt(_uploadModePrefsKey) ?? 0;
      if (idx >= 0 && idx < UploadMode.values.length) {
        _uploadMode = UploadMode.values[idx];
      }
    } else if (prefs.containsKey(_legacyTestModePrefsKey)) {
      // migrate legacy test_mode (true->simulate, false->prod)
      final legacy = prefs.getBool(_legacyTestModePrefsKey) ?? false;
      _uploadMode = legacy ? UploadMode.simulate : UploadMode.production;
      await prefs.remove(_legacyTestModePrefsKey);
      await prefs.setInt(_uploadModePrefsKey, _uploadMode.index);
    }
    // Max cameras
    if (prefs.containsKey(_maxCamerasPrefsKey)) {
      _maxCameras = prefs.getInt(_maxCamerasPrefsKey) ?? 250;
    }
    // Offline mode loading
    if (prefs.containsKey(_offlineModePrefsKey)) {
      _offlineMode = prefs.getBool(_offlineModePrefsKey) ?? false;
    }
    // Ensure AuthService follows loaded mode
    _auth.setUploadMode(_uploadMode);
    print('AppState: AuthService mode now updated to $_uploadMode');

    await _loadQueue();
    
    // Check if we're already logged in and get username
    try {
      if (await _auth.isLoggedIn()) {
        print('AppState: User appears to be logged in, fetching username...');
        _username = await _auth.login();
        if (_username != null) {
          print("AppState: Successfully retrieved username: $_username");
        } else {
          print('AppState: Failed to retrieve username despite being logged in');
        }
      } else {
        print('AppState: User is not logged in');
      }
    } catch (e) {
      print("AppState: Error during auth initialization: $e");
    }
    
    _startUploader();
    _isInitialized = true;
    notifyListeners();
  }

  // ---------- Auth ----------
  Future<void> login() async {
    try {
      print('AppState: Starting login process...');
      _username = await _auth.login();
      if (_username != null) {
        print("AppState: Login successful for user: $_username");
      } else {
        print('AppState: Login failed - no username returned');
      }
    } catch (e) {
      print("AppState: Login error: $e");
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
          print("AppState: Auth refresh successful: $_username");
        } else {
          print('AppState: Auth refresh failed - no username');
        }
      } else {
        print('AppState: No valid token found');
        _username = null;
      }
    } catch (e) {
      print("AppState: Auth refresh error: $e");
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
        print("AppState: Forced login successful: $_username");
      } else {
        print('AppState: Forced login failed - no username returned');
      }
    } catch (e) {
      print("AppState: Forced login error: $e");
      _username = null;
    }
    notifyListeners();
  }

  // Validate current token/credentials
  Future<bool> validateToken() async {
    try {
      return await _auth.isLoggedIn();
    } catch (e) {
    print("AppState: Token validation error: $e");
      return false;
    }
  }

  // ---------- Profiles ----------
  List<CameraProfile> get profiles => List.unmodifiable(_profiles);
  bool isEnabled(CameraProfile p) => _enabled.contains(p);
  List<CameraProfile> get enabledProfiles =>
      _profiles.where(isEnabled).toList(growable: false);
  void toggleProfile(CameraProfile p, bool e) {
    if (e) {
      _enabled.add(p);
    } else {
      _enabled.remove(p);
      // Safety: Always have at least one enabled profile
      if (_enabled.isEmpty) {
        final builtIn = _profiles.firstWhere((profile) => profile.builtin, orElse: () => _profiles.first);
        _enabled.add(builtIn);
      }
    }
    _saveEnabledProfiles();
    notifyListeners();
  }

  void addOrUpdateProfile(CameraProfile p) {
    final idx = _profiles.indexWhere((x) => x.id == p.id);
    if (idx >= 0) {
      _profiles[idx] = p;
    } else {
      _profiles.add(p);
      _enabled.add(p);
      _saveEnabledProfiles();
    }
    ProfileService().save(_profiles);
    notifyListeners();
  }

  void deleteProfile(CameraProfile p) {
    if (p.builtin) return;
    _enabled.remove(p);
    _profiles.removeWhere((x) => x.id == p.id);
    // Safety: Always have at least one enabled profile
    if (_enabled.isEmpty) {
      final builtIn = _profiles.firstWhere((profile) => profile.builtin, orElse: () => _profiles.first);
      _enabled.add(builtIn);
    }
    _saveEnabledProfiles();
    ProfileService().save(_profiles);
    notifyListeners();
  }

  // Save enabled profile IDs to disk
  Future<void> _saveEnabledProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _enabledPrefsKey,
      _enabled.map((p) => p.id).toList(),
    );
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

    // No uploads without auth or queue, or if offline mode is enabled.
    if (_queue.isEmpty || _offlineMode) return;

    _uploadTimer = Timer.periodic(const Duration(seconds: 10), (t) async {
      if (_queue.isEmpty || _offlineMode) {
        _uploadTimer?.cancel();
        return;
      }

      // Find the first queue item that is NOT in error state and act on that
      final item = _queue.where((pu) => !pu.error).cast<PendingUpload?>().firstOrNull;
      if (item == null) return;

      // Retrieve access after every tick (accounts for re-login)
      final access = await _auth.getAccessToken();
      if (access == null) return; // not logged in

      bool ok;
      if (_uploadMode == UploadMode.simulate) {
        // Simulate successful upload without calling real API
        print("AppState: UploadMode.simulate - simulating upload for ${item.coord}");
        await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
        ok = true;
        print('AppState: Simulated upload successful');
      } else {
        // Real upload -- pass uploadMode so uploader can switch between prod and sandbox
        final up = Uploader(access, () {
          _queue.remove(item);
          _saveQueue();
          notifyListeners();
        }, uploadMode: _uploadMode);
        ok = await up.upload(item);
      }

      if (ok && _uploadMode == UploadMode.simulate) {
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

  // ---------- Exposed getters ----------
  int get pendingCount => _queue.length;
  List<PendingUpload> get pendingUploads => List.unmodifiable(_queue);
  
  // ---------- Queue management ----------
  void clearQueue() {
    print("AppState: Clearing upload queue (${_queue.length} items)");
    _queue.clear();
    _saveQueue();
    notifyListeners();
  }
  
  void removeFromQueue(PendingUpload upload) {
    print("AppState: Removing upload from queue: ${upload.coord}");
    _queue.remove(upload);
    _saveQueue();
    notifyListeners();
  }

  // Retry a failed upload (clear error and attempts, then try uploading again)
  void retryUpload(PendingUpload upload) {
    upload.error = false;
    upload.attempts = 0;
    _saveQueue();
    notifyListeners();
    _startUploader(); // resume uploader if not busy
  }
}

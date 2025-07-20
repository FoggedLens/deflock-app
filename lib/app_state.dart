import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/camera_profile.dart';
import 'models/pending_upload.dart';
import 'services/auth_service.dart';
import 'services/uploader.dart';

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

  late final List<CameraProfile> _profiles = [CameraProfile.alpr()];
  final Set<CameraProfile> _enabled = {};

  AddCameraSession? _session;
  AddCameraSession? get session => _session;

  final List<PendingUpload> _queue = [];
  Timer? _uploadTimer;

  bool get isLoggedIn => _username != null;
  String get username => _username ?? '';

  // ---------- Init ----------
  Future<void> _init() async {
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

  // ---------- Profiles ----------
  List<CameraProfile> get profiles => List.unmodifiable(_profiles);
  bool isEnabled(CameraProfile p) => _enabled.contains(p);
  List<CameraProfile> get enabledProfiles =>
      _profiles.where(isEnabled).toList(growable: false);
  void toggleProfile(CameraProfile p, bool e) {
    e ? _enabled.add(p) : _enabled.remove(p);
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
      final up = Uploader(access, () {
        _queue.remove(item);
        _saveQueue();
        notifyListeners();
      });

      final ok = await up.upload(item);
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
}


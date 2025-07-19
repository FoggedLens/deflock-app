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
    if (await _auth.isLoggedIn()) {
      _username = await _auth.login();
    }
    _startUploader();
    notifyListeners();
  }

  // ---------- Auth ----------
  Future<void> login() async {
    _username = await _auth.login();
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.logout();
    _username = null;
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
    if (directionDeg != null) _session!.directionDegrees = directionDeg;
    if (profile != null) _session!.profile = profile;
    if (target != null) _session!.target = target;
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


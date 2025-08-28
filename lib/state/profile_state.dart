import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/camera_profile.dart';
import '../services/profile_service.dart';

class ProfileState extends ChangeNotifier {
  static const String _enabledPrefsKey = 'enabled_profiles';

  final List<CameraProfile> _profiles = [];
  final Set<CameraProfile> _enabled = {};

  // Getters
  List<CameraProfile> get profiles => List.unmodifiable(_profiles);
  bool isEnabled(CameraProfile p) => _enabled.contains(p);
  List<CameraProfile> get enabledProfiles =>
      _profiles.where(isEnabled).toList(growable: false);

  // Initialize profiles from built-in and custom sources
  Future<void> init() async {
    // Initialize profiles: built-in + custom
    _profiles.add(CameraProfile.genericAlpr());
    _profiles.add(CameraProfile.flock());
    _profiles.add(CameraProfile.motorola());
    _profiles.add(CameraProfile.genetec());
    _profiles.add(CameraProfile.leonardo());
    _profiles.add(CameraProfile.neology());
    _profiles.addAll(await ProfileService().load());

    // Load enabled profile IDs from prefs
    final prefs = await SharedPreferences.getInstance();
    final enabledIds = prefs.getStringList(_enabledPrefsKey);
    if (enabledIds != null && enabledIds.isNotEmpty) {
      // Restore enabled profiles by id
      _enabled.addAll(_profiles.where((p) => enabledIds.contains(p.id)));
    } else {
      // By default, all are enabled
      _enabled.addAll(_profiles);
    }
  }

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
}
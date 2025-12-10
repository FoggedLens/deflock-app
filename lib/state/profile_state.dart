import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/node_profile.dart';
import '../services/profile_service.dart';

class ProfileState extends ChangeNotifier {
  static const String _enabledPrefsKey = 'enabled_profiles';

  final List<NodeProfile> _profiles = [];
  final Set<NodeProfile> _enabled = {};
  
  // Callback for when a profile is deleted (used to clear stale sessions)
  void Function(NodeProfile)? _onProfileDeleted;
  
  void setProfileDeletedCallback(void Function(NodeProfile) callback) {
    _onProfileDeleted = callback;
  }

  // Getters
  List<NodeProfile> get profiles => List.unmodifiable(_profiles);
  bool isEnabled(NodeProfile p) => _enabled.contains(p);
  List<NodeProfile> get enabledProfiles =>
      _profiles.where(isEnabled).toList(growable: false);

  // Initialize profiles from built-in and custom sources
  Future<void> init({bool addDefaults = false}) async {
    // Load custom profiles from storage
    _profiles.addAll(await ProfileService().load());

    // Add built-in profiles if this is first launch
    if (addDefaults) {
      _profiles.addAll(NodeProfile.getDefaults());
      await ProfileService().save(_profiles);
    }

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

  void toggleProfile(NodeProfile p, bool e) {
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

  void addOrUpdateProfile(NodeProfile p) {
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

  void deleteProfile(NodeProfile p) {
    if (!p.editable) return;
    _enabled.remove(p);
    _profiles.removeWhere((x) => x.id == p.id);
    // Safety: Always have at least one enabled profile
    if (_enabled.isEmpty) {
      final builtIn = _profiles.firstWhere((profile) => profile.builtin, orElse: () => _profiles.first);
      _enabled.add(builtIn);
    }
    _saveEnabledProfiles();
    ProfileService().save(_profiles);
    
    // Notify about profile deletion so other parts can clean up
    _onProfileDeleted?.call(p);
    
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
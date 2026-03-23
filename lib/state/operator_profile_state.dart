import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/operator_profile.dart';
import '../services/operator_profile_service.dart';

class OperatorProfileState extends ChangeNotifier {
  static const String _profileOrderPrefsKey = 'operator_profile_order';
  
  final List<OperatorProfile> _profiles = [];
  List<String> _customOrder = []; // List of profile IDs in user's preferred order

  List<OperatorProfile> get profiles => List.unmodifiable(_getOrderedProfiles());

  Future<void> init({bool addDefaults = false}) async {
    _profiles.addAll(await OperatorProfileService().load());
    
    // Add default operator profiles if this is first launch
    if (addDefaults) {
      _profiles.addAll(OperatorProfile.getDefaults());
      await OperatorProfileService().save(_profiles);
    }
    
    // Load custom order from prefs
    final prefs = await SharedPreferences.getInstance();
    _customOrder = prefs.getStringList(_profileOrderPrefsKey) ?? [];
  }

  void addOrUpdateProfile(OperatorProfile p) {
    final idx = _profiles.indexWhere((x) => x.id == p.id);
    if (idx >= 0) {
      _profiles[idx] = p;
    } else {
      _profiles.add(p);
    }
    OperatorProfileService().save(_profiles);
    notifyListeners();
  }

  void deleteProfile(OperatorProfile p) {
    _profiles.removeWhere((x) => x.id == p.id);
    OperatorProfileService().save(_profiles);
    notifyListeners();
  }

  // Reorder profiles (for drag-and-drop in settings)
  void reorderProfiles(int oldIndex, int newIndex) {
    final orderedProfiles = _getOrderedProfiles();
    
    // Standard Flutter reordering logic
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = orderedProfiles.removeAt(oldIndex);
    orderedProfiles.insert(newIndex, item);
    
    // Update custom order with new sequence
    _customOrder = orderedProfiles.map((p) => p.id).toList();
    _saveCustomOrder();
    notifyListeners();
  }
  
  // Get profiles in custom order, with unordered profiles at the end
  List<OperatorProfile> _getOrderedProfiles() {
    if (_customOrder.isEmpty) {
      return List.from(_profiles);
    }
    
    final ordered = <OperatorProfile>[];
    final profilesById = {for (final p in _profiles) p.id: p};
    
    // Add profiles in custom order
    for (final id in _customOrder) {
      final profile = profilesById[id];
      if (profile != null) {
        ordered.add(profile);
        profilesById.remove(id);
      }
    }
    
    // Add any remaining profiles that weren't in the custom order
    ordered.addAll(profilesById.values);
    
    return ordered;
  }
  
  // Save custom order to disk
  Future<void> _saveCustomOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_profileOrderPrefsKey, _customOrder);
    } catch (e) {
      // Fail gracefully in tests or if SharedPreferences isn't available
      debugPrint('[OperatorProfileState] Failed to save custom order: $e');
    }
  }
}
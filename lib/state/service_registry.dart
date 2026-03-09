import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/service_registry_entry.dart';

/// Generic list manager for [ServiceRegistryEntry] subtypes.
///
/// Handles persistence (JSON in SharedPreferences), CRUD operations,
/// reordering, default management, and change notification.
class ServiceRegistry<T extends ServiceRegistryEntry> {
  /// SharedPreferences key for this registry's data.
  final String prefsKey;

  /// Deserialize a JSON map to a registry entry.
  final T Function(Map<String, dynamic>) fromJson;

  /// Factory for creating the default entries (built-in endpoints/tiles).
  final List<T> Function() createDefaults;

  /// Called after every mutation to notify the owning state object.
  final VoidCallback onChanged;

  List<T> _entries = [];
  SharedPreferences? _prefs;

  ServiceRegistry({
    required this.prefsKey,
    required this.fromJson,
    required this.createDefaults,
    required this.onChanged,
  });

  /// Unmodifiable view of all entries in priority order.
  List<T> get entries => List.unmodifiable(_entries);

  /// Only entries with [enabled] == true, in priority order.
  List<T> get enabledEntries =>
      _entries.where((e) => e.enabled).toList(growable: false);

  /// Load from SharedPreferences; initialize with defaults if absent or corrupt.
  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;
    if (prefs.containsKey(prefsKey)) {
      try {
        final json = jsonDecode(prefs.getString(prefsKey)!) as List;
        _entries = json
            .map((j) => fromJson(j as Map<String, dynamic>))
            .toList();
        await _addMissingDefaults();
        return;
      } catch (e) {
        debugPrint('[ServiceRegistry] Error loading $prefsKey: $e');
      }
    }
    _entries = List.of(createDefaults());
    await _save();
  }

  /// Add a new entry or update an existing one (matched by id).
  /// New entries are appended; existing entries are replaced in-place.
  Future<void> addOrUpdate(T entry) async {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      _entries[index] = entry;
    } else {
      _entries.add(entry);
    }
    await _save();
    onChanged();
  }

  /// Remove an entry by id.
  /// Throws [StateError] if this would empty the list.
  /// Throws [UnsupportedError] if the entry is built-in and we're in release mode.
  Future<void> delete(String id) async {
    final index = _entries.indexWhere((e) => e.id == id);
    if (index < 0) return;
    if (_entries.length <= 1) {
      throw StateError('Cannot delete the last entry');
    }
    if (_entries[index].isBuiltIn && !kDebugMode) {
      throw UnsupportedError('Cannot delete built-in entries in release mode');
    }
    _entries.removeAt(index);
    await _save();
    onChanged();
  }

  /// Move entry from [oldIndex] to [newIndex].
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    // ReorderableListView convention: if moving down, newIndex is +1
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final entry = _entries.removeAt(oldIndex);
    _entries.insert(adjustedNew, entry);
    await _save();
    onChanged();
  }

  /// Replace all entries with defaults.
  Future<void> resetToDefaults() async {
    _entries = List.of(createDefaults());
    await _save();
    onChanged();
  }

  /// Find an entry by id, or null if not found.
  T? findById(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Add any default entries that are missing from the current list.
  Future<void> _addMissingDefaults() async {
    final existingIds = _entries.map((e) => e.id).toSet();
    final defaults = createDefaults();
    var changed = false;
    for (final d in defaults) {
      if (!existingIds.contains(d.id)) {
        _entries.add(d);
        changed = true;
      }
    }
    if (changed) await _save();
  }

  Future<void> _save() async {
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await _prefs!.setString(prefsKey, json);
  }
}

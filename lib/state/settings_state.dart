import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../models/tile_provider.dart';
import '../dev_config.dart';

// Enum for upload mode (Production, OSM Sandbox, Simulate)
enum UploadMode { production, sandbox, simulate }

// Enum for follow-me mode (moved from HomeScreen to centralized state)
enum FollowMeMode {
  off,      // No following
  northUp,  // Follow position, keep north up
  rotating, // Follow position and rotation
}

class SettingsState extends ChangeNotifier {
  static const String _offlineModePrefsKey = 'offline_mode';
  static const String _maxCamerasPrefsKey = 'max_cameras';
  static const String _uploadModePrefsKey = 'upload_mode';
  static const String _tileProvidersPrefsKey = 'tile_providers';
  static const String _selectedTileTypePrefsKey = 'selected_tile_type';
  static const String _legacyTestModePrefsKey = 'test_mode';
  static const String _followMeModePrefsKey = 'follow_me_mode';
  static const String _proximityAlertsEnabledPrefsKey = 'proximity_alerts_enabled';
  static const String _proximityAlertDistancePrefsKey = 'proximity_alert_distance';

  bool _offlineMode = false;
  int _maxCameras = 250;
  UploadMode _uploadMode = kEnableDevelopmentModes ? UploadMode.simulate : UploadMode.production;
  FollowMeMode _followMeMode = FollowMeMode.northUp;
  bool _proximityAlertsEnabled = false;
  int _proximityAlertDistance = kProximityAlertDefaultDistance;
  List<TileProvider> _tileProviders = [];
  String _selectedTileTypeId = '';

  // Getters
  bool get offlineMode => _offlineMode;
  int get maxCameras => _maxCameras;
  UploadMode get uploadMode => _uploadMode;
  FollowMeMode get followMeMode => _followMeMode;
  bool get proximityAlertsEnabled => _proximityAlertsEnabled;
  int get proximityAlertDistance => _proximityAlertDistance;
  List<TileProvider> get tileProviders => List.unmodifiable(_tileProviders);
  String get selectedTileTypeId => _selectedTileTypeId;
  
  /// Get the currently selected tile type
  TileType? get selectedTileType {
    for (final provider in _tileProviders) {
      for (final tileType in provider.tileTypes) {
        if (tileType.id == _selectedTileTypeId) {
          return tileType;
        }
      }
    }
    return null;
  }
  
  /// Get the provider that contains the selected tile type
  TileProvider? get selectedTileProvider {
    for (final provider in _tileProviders) {
      if (provider.tileTypes.any((type) => type.id == _selectedTileTypeId)) {
        return provider;
      }
    }
    return null;
  }
  
  /// Get all available tile types from all providers
  List<TileType> get allAvailableTileTypes {
    final types = <TileType>[];
    for (final provider in _tileProviders) {
      types.addAll(provider.availableTileTypes);
    }
    return types;
  }



  // Initialize settings from preferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load offline mode
    _offlineMode = prefs.getBool(_offlineModePrefsKey) ?? false;
    
    // Load max cameras
    if (prefs.containsKey(_maxCamerasPrefsKey)) {
      _maxCameras = prefs.getInt(_maxCamerasPrefsKey) ?? 250;
    }
    
    // Load proximity alerts settings
    _proximityAlertsEnabled = prefs.getBool(_proximityAlertsEnabledPrefsKey) ?? false;
    _proximityAlertDistance = prefs.getInt(_proximityAlertDistancePrefsKey) ?? kProximityAlertDefaultDistance;
    
    // Load upload mode (including migration from old test_mode bool)
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
    
    // In production builds, force production mode if development modes are disabled
    if (!kEnableDevelopmentModes && _uploadMode != UploadMode.production) {
      debugPrint('SettingsState: Development modes disabled, forcing production mode');
      _uploadMode = UploadMode.production;
      await prefs.setInt(_uploadModePrefsKey, _uploadMode.index);
    }
    
    // Load tile providers (default to built-in providers if none saved)
    await _loadTileProviders(prefs);
    
    // Load follow-me mode
    if (prefs.containsKey(_followMeModePrefsKey)) {
      final modeIndex = prefs.getInt(_followMeModePrefsKey) ?? 0;
      if (modeIndex >= 0 && modeIndex < FollowMeMode.values.length) {
        _followMeMode = FollowMeMode.values[modeIndex];
      }
    }
    
    // Load selected tile type (default to first available)
    _selectedTileTypeId = prefs.getString(_selectedTileTypePrefsKey) ?? '';
    if (_selectedTileTypeId.isEmpty || selectedTileType == null) {
      final firstType = allAvailableTileTypes.firstOrNull;
      if (firstType != null) {
        _selectedTileTypeId = firstType.id;
        await prefs.setString(_selectedTileTypePrefsKey, _selectedTileTypeId);
      }
    }
  }

  Future<void> _loadTileProviders(SharedPreferences prefs) async {
    if (prefs.containsKey(_tileProvidersPrefsKey)) {
      try {
        final providersJson = prefs.getString(_tileProvidersPrefsKey);
        if (providersJson != null) {
          final providersList = jsonDecode(providersJson) as List;
          _tileProviders = providersList
              .map((json) => TileProvider.fromJson(json))
              .toList();
        }
      } catch (e) {
        debugPrint('Error loading tile providers: $e');
        // Fall back to defaults on error
        _tileProviders = DefaultTileProviders.createDefaults();
      }
    } else {
      // First time - use defaults
      _tileProviders = DefaultTileProviders.createDefaults();
      await _saveTileProviders(prefs);
    }
  }

  Future<void> _saveTileProviders(SharedPreferences prefs) async {
    try {
      final providersJson = jsonEncode(
        _tileProviders.map((provider) => provider.toJson()).toList(),
      );
      await prefs.setString(_tileProvidersPrefsKey, providersJson);
    } catch (e) {
      debugPrint('Error saving tile providers: $e');
    }
  }

  Future<void> setOfflineMode(bool enabled) async {
    _offlineMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineModePrefsKey, enabled);
    notifyListeners();
  }

  set maxCameras(int n) {
    if (n < 10) n = 10; // minimum
    _maxCameras = n;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_maxCamerasPrefsKey, n);
    });
    notifyListeners();
  }

  Future<void> setUploadMode(UploadMode mode) async {
    // In production builds, only allow production mode
    if (!kEnableDevelopmentModes && mode != UploadMode.production) {
      debugPrint('SettingsState: Development modes disabled, forcing production mode');
      mode = UploadMode.production;
    }
    
    _uploadMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_uploadModePrefsKey, mode.index);
    notifyListeners();
  }

  /// Select a tile type by ID
  Future<void> setSelectedTileType(String tileTypeId) async {
    if (_selectedTileTypeId != tileTypeId) {
      _selectedTileTypeId = tileTypeId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedTileTypePrefsKey, tileTypeId);
      notifyListeners();
    }
  }

  /// Add or update a tile provider
  Future<void> addOrUpdateTileProvider(TileProvider provider) async {
    final existingIndex = _tileProviders.indexWhere((p) => p.id == provider.id);
    if (existingIndex >= 0) {
      _tileProviders[existingIndex] = provider;
    } else {
      _tileProviders.add(provider);
    }
    
    final prefs = await SharedPreferences.getInstance();
    await _saveTileProviders(prefs);
    notifyListeners();
  }

  /// Delete a tile provider
  Future<void> deleteTileProvider(String providerId) async {
    // Don't allow deleting all providers
    if (_tileProviders.length <= 1) return;
    
    final providerToDelete = _tileProviders.firstWhereOrNull((p) => p.id == providerId);
    if (providerToDelete == null) return;
    
    // If selected tile type belongs to this provider, switch to another
    if (providerToDelete.tileTypes.any((type) => type.id == _selectedTileTypeId)) {
      // Find first available tile type from remaining providers
      final remainingProviders = _tileProviders.where((p) => p.id != providerId).toList();
      final firstAvailable = remainingProviders
          .expand((p) => p.availableTileTypes)
          .firstOrNull;
      
      if (firstAvailable != null) {
        _selectedTileTypeId = firstAvailable.id;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_selectedTileTypePrefsKey, _selectedTileTypeId);
      }
    }
    
    _tileProviders.removeWhere((p) => p.id == providerId);
    final prefs = await SharedPreferences.getInstance();
    await _saveTileProviders(prefs);
    notifyListeners();
  }

  /// Set follow-me mode
  Future<void> setFollowMeMode(FollowMeMode mode) async {
    if (_followMeMode != mode) {
      _followMeMode = mode;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_followMeModePrefsKey, mode.index);
      notifyListeners();
    }
  }

  /// Set proximity alerts enabled/disabled
  Future<void> setProximityAlertsEnabled(bool enabled) async {
    if (_proximityAlertsEnabled != enabled) {
      _proximityAlertsEnabled = enabled;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_proximityAlertsEnabledPrefsKey, enabled);
      notifyListeners();
    }
  }

  /// Set proximity alert distance in meters
  Future<void> setProximityAlertDistance(int distance) async {
    if (distance < kProximityAlertMinDistance) distance = kProximityAlertMinDistance;
    if (distance > kProximityAlertMaxDistance) distance = kProximityAlertMaxDistance;
    if (_proximityAlertDistance != distance) {
      _proximityAlertDistance = distance;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_proximityAlertDistancePrefsKey, distance);
      notifyListeners();
    }
  }

}
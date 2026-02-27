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
  follow,   // Follow position, preserve current rotation
  rotating, // Follow position and rotation based on heading
}

// Enum for distance units
enum DistanceUnit {
  metric,   // kilometers, meters
  imperial, // miles, feet
}

class SettingsState extends ChangeNotifier {
  static const String _offlineModePrefsKey = 'offline_mode';
  static const String _maxNodesPrefsKey = 'max_nodes';
  static const String _uploadModePrefsKey = 'upload_mode';
  static const String _tileProvidersPrefsKey = 'tile_providers';
  static const String _selectedTileTypePrefsKey = 'selected_tile_type';
  static const String _legacyTestModePrefsKey = 'test_mode';
  static const String _followMeModePrefsKey = 'follow_me_mode';
  static const String _proximityAlertsEnabledPrefsKey = 'proximity_alerts_enabled';
  static const String _proximityAlertDistancePrefsKey = 'proximity_alert_distance';
  static const String _networkStatusIndicatorEnabledPrefsKey = 'network_status_indicator_enabled';
  static const String _suspectedLocationMinDistancePrefsKey = 'suspected_location_min_distance';
  static const String _pauseQueueProcessingPrefsKey = 'pause_queue_processing';
  static const String _navigationAvoidanceDistancePrefsKey = 'navigation_avoidance_distance';
  static const String _distanceUnitPrefsKey = 'distance_unit';
  static const String _forceLocationManagerPrefsKey = 'force_location_manager';

  bool _offlineMode = false;
  bool _pauseQueueProcessing = false;
  int _maxNodes = kDefaultMaxNodes;
  UploadMode _uploadMode = kEnableDevelopmentModes ? UploadMode.simulate : UploadMode.production;
  FollowMeMode _followMeMode = FollowMeMode.follow;
  bool _proximityAlertsEnabled = false;
  int _proximityAlertDistance = kProximityAlertDefaultDistance;
  bool _networkStatusIndicatorEnabled = true;
  int _suspectedLocationMinDistance = 100; // meters
  List<TileProvider> _tileProviders = [];
  String _selectedTileTypeId = '';
  int _navigationAvoidanceDistance = 250; // meters
  DistanceUnit _distanceUnit = DistanceUnit.metric;
  bool _forceLocationManager = false;

  // Getters
  bool get offlineMode => _offlineMode;
  bool get pauseQueueProcessing => _pauseQueueProcessing;
  int get maxNodes => _maxNodes;
  UploadMode get uploadMode => _uploadMode;
  FollowMeMode get followMeMode => _followMeMode;
  bool get proximityAlertsEnabled => _proximityAlertsEnabled;
  int get proximityAlertDistance => _proximityAlertDistance;
  bool get networkStatusIndicatorEnabled => _networkStatusIndicatorEnabled;
  int get suspectedLocationMinDistance => _suspectedLocationMinDistance;
  List<TileProvider> get tileProviders => List.unmodifiable(_tileProviders);
  String get selectedTileTypeId => _selectedTileTypeId;
  int get navigationAvoidanceDistance => _navigationAvoidanceDistance;
  DistanceUnit get distanceUnit => _distanceUnit;
  bool get forceLocationManager => _forceLocationManager;

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
    
    // Load queue processing setting
    _pauseQueueProcessing = prefs.getBool(_pauseQueueProcessingPrefsKey) ?? false;
    
    // Load max nodes
    _maxNodes = prefs.getInt(_maxNodesPrefsKey) ?? kDefaultMaxNodes;

    // Load navigation avoidance distance
    if (prefs.containsKey(_navigationAvoidanceDistancePrefsKey)) {
      _navigationAvoidanceDistance = prefs.getInt(_navigationAvoidanceDistancePrefsKey) ?? 250;
    }
    
    // Load distance unit
    if (prefs.containsKey(_distanceUnitPrefsKey)) {
      final unitIndex = prefs.getInt(_distanceUnitPrefsKey) ?? 0;
      if (unitIndex >= 0 && unitIndex < DistanceUnit.values.length) {
        _distanceUnit = DistanceUnit.values[unitIndex];
      }
    }
    
    // Load proximity alerts settings
    _proximityAlertsEnabled = prefs.getBool(_proximityAlertsEnabledPrefsKey) ?? false;
    _proximityAlertDistance = prefs.getInt(_proximityAlertDistancePrefsKey) ?? kProximityAlertDefaultDistance;
    
    // Load network status indicator setting
    _networkStatusIndicatorEnabled = prefs.getBool(_networkStatusIndicatorEnabledPrefsKey) ?? true;
    
    // Load suspected location minimum distance
    _suspectedLocationMinDistance = prefs.getInt(_suspectedLocationMinDistancePrefsKey) ?? 100;

    // Load force location manager setting (default false = use Google Fused Location)
    _forceLocationManager = prefs.getBool(_forceLocationManagerPrefsKey) ?? false;
    
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
          
          // Migration: Add any missing built-in providers
          await _addMissingBuiltinProviders(prefs);
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

  /// Add any built-in providers that are missing from user's configuration
  Future<void> _addMissingBuiltinProviders(SharedPreferences prefs) async {
    final defaultProviders = DefaultTileProviders.createDefaults();
    final existingProviderIds = _tileProviders.map((p) => p.id).toSet();
    bool hasUpdates = false;
    
    for (final defaultProvider in defaultProviders) {
      if (!existingProviderIds.contains(defaultProvider.id)) {
        _tileProviders.add(defaultProvider);
        hasUpdates = true;
        debugPrint('SettingsState: Added missing built-in provider: ${defaultProvider.name}');
      }
    }
    
    if (hasUpdates) {
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

  Future<void> setPauseQueueProcessing(bool enabled) async {
    _pauseQueueProcessing = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pauseQueueProcessingPrefsKey, enabled);
    notifyListeners();
  }

  set maxNodes(int n) {
    if (n < 10) n = 10; // minimum
    _maxNodes = n;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt(_maxNodesPrefsKey, n);
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

  /// Set network status indicator enabled/disabled
  Future<void> setNetworkStatusIndicatorEnabled(bool enabled) async {
    if (_networkStatusIndicatorEnabled != enabled) {
      _networkStatusIndicatorEnabled = enabled;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_networkStatusIndicatorEnabledPrefsKey, enabled);
      notifyListeners();
    }
  }

  /// Set suspected location minimum distance from real nodes
  Future<void> setSuspectedLocationMinDistance(int distance) async {
    if (_suspectedLocationMinDistance != distance) {
      _suspectedLocationMinDistance = distance;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_suspectedLocationMinDistancePrefsKey, distance);
      notifyListeners();
    }
  }

  // Set distance for avoidance of nodes during navigation
  Future<void> setNavigationAvoidanceDistance(int distance) async {
    if (_navigationAvoidanceDistance != distance) {
      _navigationAvoidanceDistance = distance;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_navigationAvoidanceDistancePrefsKey, distance);
      notifyListeners();
    }
  }

  /// Set distance unit (metric or imperial)
  Future<void> setDistanceUnit(DistanceUnit unit) async {
    if (_distanceUnit != unit) {
      _distanceUnit = unit;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_distanceUnitPrefsKey, unit.index);
      notifyListeners();
    }
  }

  /// Set whether to force Android LocationManager instead of Google Fused Location Provider
  Future<void> setForceLocationManager(bool enabled) async {
    if (_forceLocationManager != enabled) {
      _forceLocationManager = enabled;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_forceLocationManagerPrefsKey, enabled);
      notifyListeners();
    }
  }

}

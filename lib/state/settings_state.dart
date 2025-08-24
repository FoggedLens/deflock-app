import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../models/tile_provider.dart';

// Enum for upload mode (Production, OSM Sandbox, Simulate)
enum UploadMode { production, sandbox, simulate }

class SettingsState extends ChangeNotifier {
  static const String _offlineModePrefsKey = 'offline_mode';
  static const String _maxCamerasPrefsKey = 'max_cameras';
  static const String _uploadModePrefsKey = 'upload_mode';
  static const String _tileProvidersPrefsKey = 'tile_providers';
  static const String _selectedTileTypePrefsKey = 'selected_tile_type';
  static const String _legacyTestModePrefsKey = 'test_mode';

  bool _offlineMode = false;
  int _maxCameras = 250;
  UploadMode _uploadMode = UploadMode.simulate;
  List<TileProvider> _tileProviders = [];
  String _selectedTileTypeId = '';

  // Getters
  bool get offlineMode => _offlineMode;
  int get maxCameras => _maxCameras;
  UploadMode get uploadMode => _uploadMode;
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

  /// Legacy getter for backward compatibility
  @Deprecated('Use selectedTileType instead')
  TileProviderType get tileProvider {
    // Map current selection to legacy enum for compatibility
    final selected = selectedTileType;
    if (selected == null) return TileProviderType.osmStreet;
    
    switch (selected.id) {
      case 'osm_street':
        return TileProviderType.osmStreet;
      case 'google_hybrid':
        return TileProviderType.googleHybrid;
      case 'esri_satellite':
        return TileProviderType.arcgisSatellite;
      case 'mapbox_satellite':
        return TileProviderType.mapboxSatellite;
      default:
        return TileProviderType.osmStreet;
    }
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
    
    // Load tile providers (default to built-in providers if none saved)
    await _loadTileProviders(prefs);
    
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

  /// Legacy setter for backward compatibility
  @Deprecated('Use setSelectedTileType instead')
  Future<void> setTileProvider(TileProviderType provider) async {
    // Map legacy enum to new tile type ID
    String tileTypeId;
    switch (provider) {
      case TileProviderType.osmStreet:
        tileTypeId = 'osm_street';
        break;
      case TileProviderType.googleHybrid:
        tileTypeId = 'google_hybrid';
        break;
      case TileProviderType.arcgisSatellite:
        tileTypeId = 'esri_satellite';
        break;
      case TileProviderType.mapboxSatellite:
        tileTypeId = 'mapbox_satellite';
        break;
    }
    
    await setSelectedTileType(tileTypeId);
  }
}
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tile_provider.dart';

// Enum for upload mode (Production, OSM Sandbox, Simulate)
enum UploadMode { production, sandbox, simulate }

class SettingsState extends ChangeNotifier {
  static const String _offlineModePrefsKey = 'offline_mode';
  static const String _maxCamerasPrefsKey = 'max_cameras';
  static const String _uploadModePrefsKey = 'upload_mode';
  static const String _tileProviderPrefsKey = 'tile_provider';
  static const String _legacyTestModePrefsKey = 'test_mode';

  bool _offlineMode = false;
  int _maxCameras = 250;
  UploadMode _uploadMode = UploadMode.simulate;
  TileProviderType _tileProvider = TileProviderType.osmStreet;

  // Getters
  bool get offlineMode => _offlineMode;
  int get maxCameras => _maxCameras;
  UploadMode get uploadMode => _uploadMode;
  TileProviderType get tileProvider => _tileProvider;

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
    
    // Load tile provider
    if (prefs.containsKey(_tileProviderPrefsKey)) {
      final idx = prefs.getInt(_tileProviderPrefsKey) ?? 0;
      if (idx >= 0 && idx < TileProviderType.values.length) {
        _tileProvider = TileProviderType.values[idx];
      }
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

  Future<void> setTileProvider(TileProviderType provider) async {
    _tileProvider = provider;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tileProviderPrefsKey, provider.index);
    notifyListeners();
  }
}
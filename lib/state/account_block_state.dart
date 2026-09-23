import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/osm_block_service.dart';
import 'settings_state.dart';

/// Tracks whether the current user has an active OSM DWG block.
///
/// Persisted per upload mode so the last known state survives app restarts
/// (e.g. launching offline) - a failed/inconclusive check leaves the
/// persisted value untouched rather than assuming "not blocked".
class AccountBlockState extends ChangeNotifier {
  final OSMBlockService _blockService;

  AccountBlockState({OSMBlockService? blockService})
      : _blockService = blockService ?? OSMBlockService();

  bool _isBlocked = false;

  bool get isBlocked => _isBlocked;

  /// Load the last known block state for the given upload mode.
  Future<void> init(UploadMode uploadMode) async {
    final prefs = await SharedPreferences.getInstance();
    _isBlocked = prefs.getBool(_prefsKey(uploadMode)) ?? false;
    notifyListeners();
  }

  /// Check for an active block. Returns the conclusive result (true/false),
  /// or null if the check was inconclusive (offline, error, not logged in,
  /// simulate mode). On null, the previously known state is left unchanged.
  Future<bool?> check({
    required String? accessToken,
    required UploadMode uploadMode,
  }) async {
    final result = await _blockService.checkActiveBlock(
      accessToken: accessToken,
      uploadMode: uploadMode,
    );

    if (result != null && result != _isBlocked) {
      _isBlocked = result;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey(uploadMode), result);
      notifyListeners();
    }

    return result;
  }

  /// Clear block state (called on logout).
  void clear() {
    if (_isBlocked) {
      _isBlocked = false;
      notifyListeners();
    }
  }

  String _prefsKey(UploadMode uploadMode) => 'account_blocked_${uploadMode.name}';
}

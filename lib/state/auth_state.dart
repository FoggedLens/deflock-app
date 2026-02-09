import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'settings_state.dart';

class AuthState extends ChangeNotifier {
  final AuthService _auth = AuthService();
  String? _username;

  // Getters
  bool get isLoggedIn => _username != null;
  String get username => _username ?? '';
  AuthService get authService => _auth;

  // Initialize auth state and check existing login
  Future<void> init(UploadMode uploadMode) async {
    _auth.setUploadMode(uploadMode);
    
    try {
      if (await _auth.isLoggedIn()) {
        _username = await _auth.restoreLogin();
      }
    } catch (e) {
      debugPrint("AuthState: Error during auth initialization: $e");
    }
  }

  Future<void> login() async {
    try {
      _username = await _auth.login();
    } catch (e) {
      debugPrint("AuthState: Login error: $e");
      _username = null;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.logout();
    _username = null;
    notifyListeners();
  }

  Future<void> refreshAuthState() async {
    try {
      if (await _auth.isLoggedIn()) {
        _username = await _auth.restoreLogin();
      } else {
        _username = null;
      }
    } catch (e) {
      debugPrint("AuthState: Auth refresh error: $e");
      _username = null;
    }
    notifyListeners();
  }

  Future<void> forceLogin() async {
    try {
      _username = await _auth.forceLogin();
    } catch (e) {
      debugPrint("AuthState: Forced login error: $e");
      _username = null;
    }
    notifyListeners();
  }

  Future<bool> validateToken() async {
    try {
      return await _auth.isLoggedIn();
    } catch (e) {
      debugPrint("AuthState: Token validation error: $e");
      return false;
    }
  }

  // Handle upload mode changes
  Future<void> onUploadModeChanged(UploadMode mode) async {
    _auth.setUploadMode(mode);
    
    // Refresh user display for active mode, validating token
    try {
      if (await _auth.isLoggedIn()) {
        final isValid = await validateToken();
        if (isValid) {
          _username = await _auth.restoreLogin();
        } else {
          await logout(); // This clears _username also.
        }
      } else {
        _username = null;
      }
    } catch (e) {
      _username = null;
      debugPrint("AuthState: Mode change user restoration error: $e");
    }
    notifyListeners();
  }

  Future<String?> getAccessToken() async {
    return await _auth.getAccessToken();
  }
}
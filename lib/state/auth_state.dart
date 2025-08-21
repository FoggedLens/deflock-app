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
        print('AuthState: User appears to be logged in, fetching username...');
        _username = await _auth.login();
        if (_username != null) {
          print("AuthState: Successfully retrieved username: $_username");
        } else {
          print('AuthState: Failed to retrieve username despite being logged in');
        }
      } else {
        print('AuthState: User is not logged in');
      }
    } catch (e) {
      print("AuthState: Error during auth initialization: $e");
    }
  }

  Future<void> login() async {
    try {
      print('AuthState: Starting login process...');
      _username = await _auth.login();
      if (_username != null) {
        print("AuthState: Login successful for user: $_username");
      } else {
        print('AuthState: Login failed - no username returned');
      }
    } catch (e) {
      print("AuthState: Login error: $e");
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
      print('AuthState: Refreshing auth state...');
      if (await _auth.isLoggedIn()) {
        print('AuthState: Token exists, fetching username...');
        _username = await _auth.login();
        if (_username != null) {
          print("AuthState: Auth refresh successful: $_username");
        } else {
          print('AuthState: Auth refresh failed - no username');
        }
      } else {
        print('AuthState: No valid token found');
        _username = null;
      }
    } catch (e) {
      print("AuthState: Auth refresh error: $e");
      _username = null;
    }
    notifyListeners();
  }

  Future<void> forceLogin() async {
    try {
      print('AuthState: Starting forced fresh login...');
      _username = await _auth.forceLogin();
      if (_username != null) {
        print("AuthState: Forced login successful: $_username");
      } else {
        print('AuthState: Forced login failed - no username returned');
      }
    } catch (e) {
      print("AuthState: Forced login error: $e");
      _username = null;
    }
    notifyListeners();
  }

  Future<bool> validateToken() async {
    try {
      return await _auth.isLoggedIn();
    } catch (e) {
      print("AuthState: Token validation error: $e");
      return false;
    }
  }

  // Handle upload mode changes
  Future<void> onUploadModeChanged(UploadMode mode) async {
    _auth.setUploadMode(mode);
    
    // Refresh user display for active mode, validating token
    try {
      if (await _auth.isLoggedIn()) {
        print('AuthState: Switching mode, token exists; validating...');
        final isValid = await validateToken();
        if (isValid) {
          print("AuthState: Switching mode; fetching username for $mode...");
          _username = await _auth.login();
          if (_username != null) {
            print("AuthState: Switched mode, now logged in as $_username");
          } else {
            print('AuthState: Switched mode but failed to retrieve username');
          }
        } else {
          print('AuthState: Switching mode, token invalid—auto-logout.');
          await logout(); // This clears _username also.
        }
      } else {
        _username = null;
        print("AuthState: Mode change: not logged in in $mode");
      }
    } catch (e) {
      _username = null;
      print("AuthState: Mode change user restoration error: $e");
    }
    notifyListeners();
  }

  Future<String?> getAccessToken() async {
    return await _auth.getAccessToken();
  }
}
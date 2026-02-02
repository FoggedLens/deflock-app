import 'dart:convert';
import 'dart:developer';

import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Handles PKCE OAuth login with OpenStreetMap.
import '../keys.dart';
import '../app_state.dart' show UploadMode;

class AuthService {
  // Both client IDs from keys.dart
  static const _redirect = 'deflockapp://auth';

  late OAuth2Helper _helper;
  String? _displayName;
  UploadMode _mode = UploadMode.production;

  AuthService({UploadMode mode = UploadMode.production}) {
    setUploadMode(mode);
  }

  String get _tokenKey {
    switch (_mode) {
      case UploadMode.production:
        return 'osm_token_prod';
      case UploadMode.sandbox:
        return 'osm_token_sandbox';
      case UploadMode.simulate:
        return 'osm_token_simulate';
    }
  }

  void setUploadMode(UploadMode mode) {
    _mode = mode;
    final isSandbox = (mode == UploadMode.sandbox);
    final authBase = isSandbox
      ? 'https://master.apis.dev.openstreetmap.org'
      : 'https://www.openstreetmap.org';
    final clientId = isSandbox ? kOsmSandboxClientId : kOsmProdClientId;
    final client = OAuth2Client(
      authorizeUrl: '$authBase/oauth2/authorize',
      tokenUrl: '$authBase/oauth2/token',
      redirectUri: _redirect,
      customUriScheme: 'deflockapp',
    );
    _helper = OAuth2Helper(
      client,
      clientId: clientId,
      scopes: ['read_prefs', 'write_api', 'consume_messages'],
      enablePKCE: true,
      // tokenStorageKey: _tokenKey, // not supported by this package version
    );
  }

  Future<bool> isLoggedIn() async {
    if (_mode == UploadMode.simulate) {
      // In simulate, a login is faked by writing to shared prefs
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('sim_user_logged_in') ?? false;
    }
    // Manually check for mode-specific token
    final prefs = await SharedPreferences.getInstance();
    final tokenJson = prefs.getString(_tokenKey);
    if (tokenJson == null) return false;
    try {
      final data = jsonDecode(tokenJson);
      return data['accessToken'] != null && data['accessToken'].toString().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String? get displayName => _displayName;

  Future<String?> login() async {
    if (_mode == UploadMode.simulate) {
      final prefs = await SharedPreferences.getInstance();
      _displayName = 'Demo User';
      await prefs.setBool('sim_user_logged_in', true);
      return _displayName;
    }
    try {
      final token = await _helper.getToken();
      if (token?.accessToken == null) {
        log('OAuth error: token null or missing accessToken');
        return null;
      }
      final tokenMap = {
        'accessToken': token!.accessToken,
        'refreshToken': token.refreshToken,
      };
      final tokenJson = jsonEncode(tokenMap);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, tokenJson); // Save token for current mode
      _displayName = await _fetchUsername(token.accessToken!);
      return _displayName;
    } catch (e) {
      print('AuthService: OAuth login failed: $e');
      log('OAuth login failed: $e');
      rethrow;
    }
  }

  // Restore login state from stored token (for app startup)
  Future<String?> restoreLogin() async {
    if (_mode == UploadMode.simulate) {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('sim_user_logged_in') ?? false;
      if (isLoggedIn) {
        _displayName = 'Demo User';
        return _displayName;
      }
      return null;
    }
    
    // Get stored token directly from SharedPreferences
    final accessToken = await getAccessToken();
    if (accessToken == null) {
      return null;
    }
    
    try {
      _displayName = await _fetchUsername(accessToken);
      return _displayName;
    } catch (e) {
      print('AuthService: Error restoring login with stored token: $e');
      log('Error restoring login with stored token: $e');
      // Token might be expired or invalid, clear it
      await logout();
      return null;
    }
  }

  Future<void> logout() async {
    if (_mode == UploadMode.simulate) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sim_user_logged_in');
      _displayName = null;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await _helper.removeAllTokens();
    _displayName = null;
  }

  // Force a fresh login by clearing stored tokens
  Future<String?> forceLogin() async {
    await _helper.removeAllTokens();
    _displayName = null;
    return await login();
  }

  Future<String?> getAccessToken() async {
    if (_mode == UploadMode.simulate) {
      return 'sim-user-token';
    }
    final prefs = await SharedPreferences.getInstance();
    final tokenJson = prefs.getString(_tokenKey);
    if (tokenJson == null) return null;
    try {
      final data = jsonDecode(tokenJson);
      return data['accessToken'];
    } catch (_) {
      return null;
    }
  }

  /* ───────── helper ───────── */

  String get _apiHost {
    return _mode == UploadMode.sandbox
      ? 'https://api06.dev.openstreetmap.org'
      : 'https://api.openstreetmap.org';
  }

  Future<String?> _fetchUsername(String accessToken) async {
    try {
      final resp = await http.get(
        Uri.parse('$_apiHost/api/0.6/user/details.json'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      
      if (resp.statusCode != 200) {
        log('fetchUsername response ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final userData = jsonDecode(resp.body);
      final displayName = userData['user']?['display_name'];
      return displayName;
    } catch (e) {
      print('AuthService: Error fetching username: $e');
      log('Error fetching username: $e');
      return null;
    }
  }
}


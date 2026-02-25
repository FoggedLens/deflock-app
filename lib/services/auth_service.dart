import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles PKCE OAuth login with OpenStreetMap.
import '../keys.dart';
import '../app_state.dart' show UploadMode;
import 'http_client.dart';

class AuthService {
  // Both client IDs from keys.dart
  static const _redirect = 'deflockapp://auth';
  static const Duration _timeout = Duration(seconds: 10);
  /// Per-mode cached display name key, parallels [_tokenKey].
  String get _cachedDisplayNameKey => 'cached_display_name_${_mode.name}';

  late OAuth2Helper _helper;
  final http.Client _client;
  String? _displayName;
  UploadMode _mode = UploadMode.production;

  AuthService({UploadMode mode = UploadMode.production, http.Client? client})
      : _client = client ?? UserAgentClient() {
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
        log('[AuthService] OAuth error: token null or missing accessToken');
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
      debugPrint('[AuthService] OAuth login failed: $e');
      log('[AuthService] OAuth login failed: $e');
      rethrow;
    }
  }

  // Restore login state from stored token (for app startup — hits network)
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

    // Try to fetch username from API; fall back to cached name on network
    // errors but log out on auth errors (401/403 = token is invalid).
    try {
      _displayName = await _fetchUsername(accessToken);
    } on _TokenRejectedException {
      debugPrint('[AuthService] Token rejected, logging out');
      await logout();
      return null;
    }
    if (_displayName == null) {
      final prefs = await SharedPreferences.getInstance();
      _displayName = prefs.getString(_cachedDisplayNameKey) ?? '';
      debugPrint('[AuthService] Using cached display name: $_displayName');
    }
    return _displayName;
  }

  /// Restore login from local cache only (no network). For use during init.
  Future<String?> restoreLoginLocal() async {
    if (_mode == UploadMode.simulate) {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('sim_user_logged_in') ?? false;
      if (isLoggedIn) {
        _displayName = 'Demo User';
        return _displayName;
      }
      return null;
    }

    final accessToken = await getAccessToken();
    if (accessToken == null) {
      return null;
    }

    // We have a token, so restore from cached display name (no network)
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString(_cachedDisplayNameKey) ?? '';
    debugPrint('[AuthService] Restored login locally: $_displayName');
    return _displayName;
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
    await prefs.remove(_cachedDisplayNameKey);
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

  /// Fetch username from OSM API.
  ///
  /// Returns the display name on success, `null` on network/server errors.
  /// Throws [_TokenRejectedException] on 401/403 so callers can log out.
  Future<String?> _fetchUsername(String accessToken) async {
    try {
      final resp = await _client.get(
        Uri.parse('$_apiHost/api/0.6/user/details.json'),
        headers: {'Authorization': 'Bearer $accessToken'},
      ).timeout(_timeout);

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        log('[AuthService] Token rejected (${resp.statusCode})');
        throw _TokenRejectedException(resp.statusCode);
      }
      if (resp.statusCode != 200) {
        log('[AuthService] fetchUsername response ${resp.statusCode}: ${resp.body}');
        return null;
      }
      final userData = jsonDecode(resp.body);
      final displayName = userData['user']?['display_name'];
      if (displayName != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cachedDisplayNameKey, displayName);
      }
      return displayName;
    } on _TokenRejectedException {
      rethrow;
    } catch (e) {
      debugPrint('[AuthService] Error fetching username: $e');
      log('[AuthService] Error fetching username: $e');
      return null;
    }
  }
}

class _TokenRejectedException implements Exception {
  final int statusCode;
  _TokenRejectedException(this.statusCode);
}

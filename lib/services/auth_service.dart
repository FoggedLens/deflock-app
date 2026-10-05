import 'dart:convert';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles PKCE OAuth login with OpenStreetMap.
import '../keys.dart';
import '../dev_config.dart';
import '../app_state.dart' show UploadMode;
import 'http_client.dart';
import 'osm_block_service.dart';

/// Thrown when the OAuth token exchange succeeds but a subsequent
/// authenticated API call (e.g. fetching the username) fails. Carries the
/// HTTP status code so callers can distinguish e.g. a 403 (often indicating
/// an active account block) from other failures.
class AuthApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  AuthApiException(this.message, {this.statusCode, this.body});

  @override
  String toString() => 'AuthApiException: $message (status: $statusCode)';
}

/// Thrown when the OAuth token exchange succeeds but the account turns out
/// to have an active OSM DWG block. Detected by checking the
/// `user/blocks/active` endpoint (which is accessible even while blocked)
/// immediately after obtaining the token, before attempting any other
/// authenticated call that would otherwise fail with a 403.
class AccountBlockedException implements Exception {
  @override
  String toString() => 'AccountBlockedException: account has an active OSM block';
}

class AuthService {
  // Both client IDs from keys.dart
  static const _redirect = 'deflockapp://auth';

  late OAuth2Helper _helper;
  String? _displayName;
  UploadMode _mode = UploadMode.production;
  final OSMBlockService _blockService;

  AuthService({UploadMode mode = UploadMode.production, OSMBlockService? blockService})
      : _blockService = blockService ?? OSMBlockService() {
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
    if (mode == UploadMode.simulate || !kHasOsmSecrets) return;
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
      if (token.accessToken == null) {
        debugPrint('AuthService: OAuth error: token null or missing accessToken (status: ${token.httpStatusCode}, error: ${token.error})');
        log('OAuth error: token null or missing accessToken');
        throw AuthApiException(
          'OAuth token exchange did not return an access token',
          statusCode: token.httpStatusCode,
        );
      }
      final tokenMap = {
        'accessToken': token.accessToken,
        'refreshToken': token.refreshToken,
      };
      final tokenJson = jsonEncode(tokenMap);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, tokenJson); // Save token for current mode

      if (kCheckBlockBeforeUsernameFetch) {
        // Check for an active block *before* fetching the username or
        // anything else. As of writing, a blocked account's OAuth token
        // exchange succeeds normally, but nearly every other authenticated
        // endpoint (including user/details) returns 403. The blocks/active
        // endpoint is explicitly documented as accessible even while
        // blocked, so checking it first lets us detect this case reliably
        // instead of getting a mysterious 403 from _fetchUsername with no
        // way to tell why.
        final isBlocked = await _blockService.checkActiveBlock(
          accessToken: token.accessToken,
          uploadMode: _mode,
        );
        if (isBlocked == true) {
          debugPrint('AuthService: Login succeeded but account has an active block');
          throw AccountBlockedException();
        }
      }

      // Fetching the username can still fail even though the OAuth token
      // exchange succeeded (e.g. if OSM ever allows this call to succeed for
      // blocked accounts, kCheckBlockBeforeUsernameFetch would be false and
      // we'd only find out here). Don't swallow that - the token is already
      // saved, so the caller needs to know the login isn't actually usable
      // rather than silently treating it as "not logged in".
      try {
        _displayName = await _fetchUsername(token.accessToken!);
      } on AuthApiException {
        // When we skipped the proactive check above, a 403 here could still
        // mean the account is blocked - check blocks/active now so we can
        // report that specifically instead of a generic auth failure.
        if (!kCheckBlockBeforeUsernameFetch) {
          final isBlocked = await _blockService.checkActiveBlock(
            accessToken: token.accessToken,
            uploadMode: _mode,
          );
          if (isBlocked == true) {
            debugPrint('AuthService: user/details failed and account has an active block');
            throw AccountBlockedException();
          }
        }
        rethrow;
      }
      return _displayName;
    } on AccountBlockedException {
      rethrow;
    } on AuthApiException {
      rethrow;
    } catch (e) {
      debugPrint('AuthService: OAuth login failed: $e');
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
      debugPrint('AuthService: Error restoring login with stored token: $e');
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
    if (_mode != UploadMode.simulate) {
      await _helper.removeAllTokens();
    }
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

  final _client = UserAgentClient();

  Future<String?> _fetchUsername(String accessToken) async {
    final http.Response resp;
    try {
      resp = await _client.get(
        Uri.parse('$_apiHost/api/0.6/user/details.json'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    } catch (e) {
      // Network-level failure (no connection, timeout, etc.) - not
      // indicative of a block, just a connectivity problem.
      debugPrint('AuthService: Error fetching username: $e');
      log('Error fetching username: $e');
      rethrow;
    }

    if (resp.statusCode != 200) {
      // A non-200 here (very commonly 403) after a successful OAuth token
      // exchange is a strong signal of an active account block. Surface it
      // loudly via debugPrint (visible in a normal release/profile console,
      // unlike dart:developer's log()) and throw instead of silently
      // returning null, so the caller can show a real error to the user.
      debugPrint('AuthService: fetchUsername failed - HTTP ${resp.statusCode}: ${resp.body}');
      log('fetchUsername response ${resp.statusCode}: ${resp.body}');
      throw AuthApiException(
        'Failed to fetch user details after login',
        statusCode: resp.statusCode,
        body: resp.body,
      );
    }
    final userData = jsonDecode(resp.body);
    final displayName = userData['user']?['display_name'];
    return displayName;
  }
}


import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Handles PKCE OAuth login with OpenStreetMap.
import '../keys.dart';
import '../app_state.dart' show UploadMode;

class AuthService {
  // Both client IDs from keys.dart
  static const _redirect = 'flockmap://auth';

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
      default:
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
      customUriScheme: 'flockmap',
    );
    _helper = OAuth2Helper(
      client,
      clientId: clientId,
      scopes: ['read_prefs', 'write_api'],
      enablePKCE: true,
      // tokenStorageKey: _tokenKey, // not supported by this package version
    );
    print('AuthService: Initialized for $mode with $authBase, clientId $clientId [manual token storage as needed]');
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
      print('AuthService: Simulate login (no OAuth)');
      final prefs = await SharedPreferences.getInstance();
      _displayName = 'Demo User';
      await prefs.setBool('sim_user_logged_in', true);
      return _displayName;
    }
    try {
      print('AuthService: Starting OAuth login...');
      final token = await _helper.getToken();
      if (token?.accessToken == null) {
        print('AuthService: OAuth error - token null or missing accessToken');
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
      print('AuthService: Got access token, fetching username...');
      _displayName = await _fetchUsername(token!.accessToken!);
      if (_displayName != null) {
        print('AuthService: Successfully fetched username: $_displayName');
      } else {
        print('AuthService: Failed to fetch username from OSM API');
      }
      return _displayName;
    } catch (e) {
      print('AuthService: OAuth login failed: $e');
      log('OAuth login failed: $e');
      rethrow;
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
    print('AuthService: Forcing fresh login by clearing stored tokens...');
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
      print('AuthService: Fetching username from OSM API ($_apiHost) ...');
      print('AuthService: Access token (first 20 chars): ${accessToken.substring(0, math.min(20, accessToken.length))}...');
      
      final resp = await http.get(
        Uri.parse('$_apiHost/api/0.6/user/details.json'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      print('AuthService: OSM API response status: ${resp.statusCode}');
      print('AuthService: Response headers: ${resp.headers}');
      
      if (resp.statusCode != 200) {
        print('AuthService: fetchUsername failed with ${resp.statusCode}: ${resp.body}');
        log('fetchUsername response ${resp.statusCode}: ${resp.body}');
        
        // Try to get more info about the token by checking permissions endpoint
        try {
          print('AuthService: Checking token permissions...');
          final permResp = await http.get(
            Uri.parse('$_apiHost/api/0.6/permissions.json'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );
          print('AuthService: Permissions response ${permResp.statusCode}: ${permResp.body}');
        } catch (e) {
          print('AuthService: Error checking permissions: $e');
        }
        
        return null;
      }
      final userData = jsonDecode(resp.body);
      final displayName = userData['user']?['display_name'];
      print('AuthService: Extracted display name: $displayName');
      return displayName;
    } catch (e) {
      print('AuthService: Error fetching username: $e');
      log('Error fetching username: $e');
      return null;
    }
  }
}


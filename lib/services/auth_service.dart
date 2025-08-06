import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:http/http.dart' as http;

/// Handles PKCE OAuth login with OpenStreetMap.
import '../app_state.dart';

import '../keys.dart';

class AuthService {
  // Both client IDs from keys.dart
  static const _redirect = 'flockmap://auth';

  late OAuth2Helper _helper;
  String? _displayName;
  UploadMode _mode = UploadMode.production;

  AuthService({UploadMode mode = UploadMode.production}) {
    setUploadMode(mode);
  }

  void setUploadMode(UploadMode mode) {
    _mode = mode;
    final isSandbox = (mode == UploadMode.sandbox);
    final authBase = isSandbox
      ? 'https://master.apis.dev.openstreetmap.org' // sandbox auth
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
    );
    print('AuthService: Initialized for $mode with $authBase and clientId $clientId');
  }

  Future<bool> isLoggedIn() async =>
      (await _helper.getTokenFromStorage())?.isExpired() == false;

  String? get displayName => _displayName;

  Future<String?> login() async {
    try {
      print('AuthService: Starting OAuth login...');
      final token = await _helper.getToken();
      if (token?.accessToken == null) {
        print('AuthService: OAuth error - token null or missing accessToken');
        log('OAuth error: token null or missing accessToken');
        return null;
      }
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

  Future<String?> getAccessToken() async =>
      (await _helper.getTokenFromStorage())?.accessToken;

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


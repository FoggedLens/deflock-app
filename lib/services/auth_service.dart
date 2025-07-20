import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:http/http.dart' as http;

/// Handles PKCE OAuth login with OpenStreetMap.
class AuthService {
  static const String _clientId = 'Js6Fn3NR3HEGaD0ZIiHBQlV9LrVcHmsOsDmApHtSyuY';
  static const _redirect = 'flockmap://auth';

  late final OAuth2Helper _helper;
  String? _displayName;

  AuthService() {
    final client = OAuth2Client(
      authorizeUrl: 'https://www.openstreetmap.org/oauth2/authorize',
      tokenUrl: 'https://www.openstreetmap.org/oauth2/token',
      redirectUri: _redirect,
      customUriScheme: 'flockmap',
    );

    _helper = OAuth2Helper(
      client,
      clientId: _clientId,
      scopes: ['read_prefs', 'write_api'],
      enablePKCE: true,
    );
    
    print('AuthService: Initialized with scopes: [read_prefs, write_api]');
    print('AuthService: Client ID: $_clientId');
    print('AuthService: Redirect URI: $_redirect');
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

  Future<String?> _fetchUsername(String accessToken) async {
    try {
      print('AuthService: Fetching username from OSM API...');
      print('AuthService: Access token (first 20 chars): ${accessToken.substring(0, math.min(20, accessToken.length))}...');
      
      final resp = await http.get(
        Uri.parse('https://api.openstreetmap.org/api/0.6/user/details.json'),
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
            Uri.parse('https://api.openstreetmap.org/api/0.6/permissions.json'),
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


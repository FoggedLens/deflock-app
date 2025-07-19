import 'dart:convert';
import 'dart:developer';

import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:http/http.dart' as http;

/// Handles PKCE OAuth login with OpenStreetMap.
class AuthService {
  /// Paste the **client ID** shown on the OSM OAuth2 application page
  /// (it can be alphanumeric like ‘lzEr2zjBGZ2…’).
  static const String _clientId = 'lzEr2zjBGZ2TvJWr3QGxNcKxigp-mQ6pRWIUhI_Bqx8';
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
      scopes: ['write_api'],
      enablePKCE: true,
    );
  }

  Future<bool> isLoggedIn() async =>
      (await _helper.getTokenFromStorage())?.isExpired() == false;

  String? get displayName => _displayName;

  Future<String?> login() async {
    try {
      final token = await _helper.getToken();
      if (token?.accessToken == null) {
        log('OAuth error: token null or missing accessToken');
        return null;
      }
      _displayName = await _fetchUsername(token!.accessToken!);
      return _displayName;
    } catch (e) {
      log('OAuth login failed: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    await _helper.removeAllTokens();
    _displayName = null;
  }

  Future<String?> getAccessToken() async =>
      (await _helper.getTokenFromStorage())?.accessToken;

  /* ───────── helper ───────── */

  Future<String?> _fetchUsername(String accessToken) async {
    final resp = await http.get(
      Uri.parse('https://api.openstreetmap.org/api/0.6/user/details.json'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (resp.statusCode != 200) {
      log('fetchUsername response ${resp.statusCode}: ${resp.body}');
      return null;
    }
    return jsonDecode(resp.body)['user']?['display_name'];
  }
}


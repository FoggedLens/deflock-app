import 'dart:convert';

import 'package:oauth2_client/oauth2_client.dart';
import 'package:oauth2_client/oauth2_helper.dart';
import 'package:http/http.dart' as http;

/// Handles OAuth 2 PKCE login to OpenStreetMap and exposes
/// the stored access token & display name.
///
/// ─ Requirements ─
/// • Register an OAuth app at
///   https://www.openstreetmap.org/oauth2/applications
///   ‑ Redirect URI: flockmap://auth
/// • Put that client ID below (replace 'flockmap').
class AuthService {
  static const _clientId = 'lzEr2zjBGZ2TvJWr3QGxNcKxigp-mQ6pRWIUhI_Bqx8';
  static const _redirect = 'flockmap://auth';

  late final OAuth2Helper _helper;

  String? _displayName; // cached after login
  String? get displayName => _displayName;

  AuthService() {
    final client = OAuth2Client(
      authorizeUrl: 'https://www.openstreetmap.org/oauth2/authorize',
      tokenUrl: 'https://www.openstreetmap.org/oauth2/token',
      redirectUri: _redirect,
      customUriScheme: 'flockmap',             // matches redirect scheme
    );

    _helper = OAuth2Helper(
      client,
      clientId: _clientId,
      scopes: ['write_api'],
      enablePKCE: true,                        // PKCE flow
      // No custom token store needed: oauth2_client will
      // auto‑use flutter_secure_storage when present.
    );
  }

  /* ───────── Public helpers ───────── */

  /// Returns `true` if a non‑expired token is stored.
  Future<bool> isLoggedIn() async =>
      (await _helper.getTokenFromStorage())?.isExpired() == false;

  /// Launches browser login if necessary; caches display name.
  Future<String?> login() async {
    final token = await _helper.getToken();
    if (token?.accessToken == null) return null;
    _displayName = await _fetchUsername(token!.accessToken!);
    return _displayName;
  }

  Future<void> logout() async {
    await _helper.removeAllTokens();
    _displayName = null;
  }

  /// Safely fetch current access token (or null).
  Future<String?> getAccessToken() async =>
      (await _helper.getTokenFromStorage())?.accessToken;

  /* ───────── Internal ───────── */

  Future<String?> _fetchUsername(String accessToken) async {
    final resp = await http.get(
      Uri.parse('https://api.openstreetmap.org/api/0.6/user/details.json'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (resp.statusCode != 200) return null;
    return jsonDecode(resp.body)['user']?['display_name'];
  }
}


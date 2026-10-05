import 'dart:convert';
import 'package:http/http.dart' as http;
import '../state/settings_state.dart';
import 'http_client.dart';

/// Service for checking whether the current user has an active OSM DWG block.
///
/// See: https://wiki.openstreetmap.org/wiki/API_v0.6#List_active_blocks:_GET_/api/0.6/user/blocks/active
class OSMBlockService {
  final http.Client _client;

  OSMBlockService({http.Client? client}) : _client = client ?? UserAgentClient();

  /// Returns whether the user currently has an active block.
  ///
  /// Returns null if not logged in, in simulate mode, or on any error
  /// (including no network connection) - callers should treat null as
  /// "unknown, assume unchanged" rather than "not blocked".
  Future<bool?> checkActiveBlock({
    required String? accessToken,
    required UploadMode uploadMode,
  }) async {
    if (uploadMode == UploadMode.simulate) return null;
    if (accessToken == null || accessToken.isEmpty) return null;

    try {
      final apiHost = _getApiHost(uploadMode);
      final response = await _client.get(
        Uri.parse('$apiHost/api/0.6/user/blocks/active.json'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      final userBlocks = data['user_blocks'];
      if (userBlocks is! List) return null;

      return userBlocks.isNotEmpty;
    } catch (e) {
      return null;
    }
  }

  String _getApiHost(UploadMode uploadMode) {
    switch (uploadMode) {
      case UploadMode.production:
        return 'https://api.openstreetmap.org';
      case UploadMode.sandbox:
        return 'https://api06.dev.openstreetmap.org';
      case UploadMode.simulate:
        return 'https://api.openstreetmap.org';
    }
  }
}

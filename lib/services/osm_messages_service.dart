import 'dart:convert';
import 'package:http/http.dart' as http;
import '../state/settings_state.dart';

/// Service for checking OSM user messages
class OSMMessagesService {
  static const _messageCheckCacheDuration = Duration(minutes: 5);
  
  DateTime? _lastCheck;
  int? _lastUnreadCount;
  UploadMode? _lastMode;

  /// Get the number of unread messages for the current user
  /// Returns null if not logged in, on error, or in simulate mode
  Future<int?> getUnreadMessageCount({
    required String? accessToken,
    required UploadMode uploadMode,
    bool forceRefresh = false,
  }) async {
    // No messages in simulate mode
    if (uploadMode == UploadMode.simulate) {
      return null;
    }
    
    // No access token means not logged in
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    
    // Check cache unless forced refresh or mode changed
    if (!forceRefresh && 
        _lastCheck != null && 
        _lastUnreadCount != null &&
        _lastMode == uploadMode &&
        DateTime.now().difference(_lastCheck!) < _messageCheckCacheDuration) {
      return _lastUnreadCount;
    }
    
    try {
      final apiHost = _getApiHost(uploadMode);
      final response = await http.get(
        Uri.parse('$apiHost/api/0.6/user/details.json'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      
      if (response.statusCode != 200) {
        return null;
      }
      
      final data = jsonDecode(response.body);
      final user = data['user'];
      if (user == null) return null;
      
      // OSM API returns message counts in user details
      final messages = user['messages'];
      if (messages == null) return null;
      
      // Get unread count
      final unreadCount = messages['unread']?['count'] ?? 0;
      
      // Update cache
      _lastCheck = DateTime.now();
      _lastUnreadCount = unreadCount;
      _lastMode = uploadMode;
      
      return unreadCount;
      
    } catch (e) {
      // Don't throw - just return null on any error
      return null;
    }
  }
  
  /// Get the URL to view messages on OSM website
  String getMessagesUrl(UploadMode uploadMode) {
    switch (uploadMode) {
      case UploadMode.production:
        return 'https://www.openstreetmap.org/messages/inbox';
      case UploadMode.sandbox:
        return 'https://master.apis.dev.openstreetmap.org/messages/inbox';
      case UploadMode.simulate:
        return 'https://www.openstreetmap.org/messages/inbox';
    }
  }
  
  /// Clear the cache (useful when user logs out or changes mode)
  void clearCache() {
    _lastCheck = null;
    _lastUnreadCount = null;
    _lastMode = null;
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
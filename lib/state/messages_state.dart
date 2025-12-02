import 'package:flutter/material.dart';
import '../services/osm_messages_service.dart';
import 'settings_state.dart';

/// State management for OSM message notifications
class MessagesState extends ChangeNotifier {
  final OSMMessagesService _messagesService = OSMMessagesService();
  
  int? _unreadCount;
  bool _isChecking = false;
  
  // Getters
  int? get unreadCount => _unreadCount;
  bool get hasUnreadMessages => (_unreadCount ?? 0) > 0;
  bool get isChecking => _isChecking;
  
  /// Check for unread messages
  Future<void> checkMessages({
    required String? accessToken,
    required UploadMode uploadMode,
    bool forceRefresh = false,
  }) async {
    if (_isChecking) return; // Prevent concurrent checks
    
    _isChecking = true;
    notifyListeners();
    
    try {
      final count = await _messagesService.getUnreadMessageCount(
        accessToken: accessToken,
        uploadMode: uploadMode,
        forceRefresh: forceRefresh,
      );
      
      if (_unreadCount != count) {
        _unreadCount = count;
        notifyListeners();
      }
    } catch (e) {
      // Silently handle errors - messages are not critical
      debugPrint('MessagesState: Error checking messages: $e');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }
  
  /// Get the URL to view messages
  String getMessagesUrl(UploadMode uploadMode) {
    return _messagesService.getMessagesUrl(uploadMode);
  }
  
  /// Clear message state (when user logs out or changes mode)
  void clearMessages() {
    _unreadCount = null;
    _messagesService.clearCache();
    notifyListeners();
  }
}
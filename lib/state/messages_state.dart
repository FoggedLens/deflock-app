import 'package:flutter/material.dart';
import '../services/osm_messages_service.dart';
import '../services/changeset_comments_service.dart';
import 'settings_state.dart';

/// State management for OSM message and changeset comment notifications
class MessagesState extends ChangeNotifier {
  final OSMMessagesService _messagesService = OSMMessagesService();
  final ChangesetCommentsService _changesetCommentsService = ChangesetCommentsService();
  
  int? _unreadCount;
  int? _unreadChangesetId; // ID of a changeset with unread comments, if any
  bool _isChecking = false;
  
  // Getters
  int? get unreadCount => _unreadCount;
  bool get hasUnreadMessages => (_unreadCount ?? 0) > 0;
  bool get hasUnreadChangesetComments => _unreadChangesetId != null;
  bool get hasUnreadNotifications => hasUnreadMessages || hasUnreadChangesetComments;
  bool get isChecking => _isChecking;
  
  /// Check for unread messages and changeset comments
  Future<void> checkMessages({
    required String? accessToken,
    required String? username,
    required UploadMode uploadMode,
    bool forceRefresh = false,
  }) async {
    if (_isChecking) return; // Prevent concurrent checks
    
    _isChecking = true;
    notifyListeners();
    
    try {
      final results = await Future.wait([
        _messagesService.getUnreadMessageCount(
          accessToken: accessToken,
          uploadMode: uploadMode,
          forceRefresh: forceRefresh,
        ),
        _changesetCommentsService.getUnreadChangesetId(
          username: username,
          uploadMode: uploadMode,
          forceRefresh: forceRefresh,
        ),
      ]);
      
      final count = results[0] as int?;
      final unreadChangesetId = results[1] as int?;
      
      if (_unreadCount != count || _unreadChangesetId != unreadChangesetId) {
        _unreadCount = count;
        _unreadChangesetId = unreadChangesetId;
        notifyListeners();
      }
    } catch (e) {
      // Silently handle errors - notifications are not critical
      debugPrint('MessagesState: Error checking messages: $e');
    } finally {
      _isChecking = false;
      notifyListeners();
    }
  }
  
  /// URL of the changeset with unread comments, on OSM's website, or null
  /// if there are no unread changeset comments.
  String? getUnreadChangesetUrl(UploadMode uploadMode) {
    final id = _unreadChangesetId;
    if (id == null) return null;
    return _changesetCommentsService.getChangesetUrl(id, uploadMode);
  }
  
  /// Mark changeset comments as read (called when user views the changeset on OSM)
  Future<void> markChangesetCommentsRead({
    required String? username,
    required UploadMode uploadMode,
  }) async {
    await _changesetCommentsService.markRead(username: username, uploadMode: uploadMode);
    if (_unreadChangesetId != null) {
      _unreadChangesetId = null;
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
    _unreadChangesetId = null;
    _messagesService.clearCache();
    _changesetCommentsService.clearCache();
    notifyListeners();
  }
}

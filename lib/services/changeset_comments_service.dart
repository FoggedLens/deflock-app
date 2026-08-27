import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../state/settings_state.dart';
import 'http_client.dart';

/// Tracks unread comments on the user's own changesets.
///
/// The OSM API has no "read" concept for changeset comments, so we track it
/// ourselves: we remember the `comments_count` we last saw for each of the
/// user's recent changesets, and flag a changeset as having unread comments
/// if it now has a higher count than what we last recorded.
///
/// This only looks at the user's most recent 100 changesets (the OSM API's
/// max page size, and it doesn't support simple offset paging). If a
/// changeset receives a new comment and then ages out of that window
/// entirely before the next check, we will miss it - an accepted limitation
/// of polling a bounded recent-activity window rather than a real
/// notification feed.
class ChangesetCommentsService {
  static const _cacheDuration = Duration(minutes: 5);
  final _client = UserAgentClient();

  DateTime? _lastCheck;
  int? _lastResult; // ID of changeset with unread comments, or null if none
  bool _lastResultIsSet = false; // whether _lastResult holds a valid cached value
  UploadMode? _lastMode;

  /// Returns the ID of a changeset with more comments now than the last
  /// time [markRead] was called for this upload mode, or null if there are
  /// none (or if not logged in, in simulate mode, or on error). When
  /// multiple changesets have new comments, returns the most recent one
  /// (the API returns changesets newest-first).
  Future<int?> getUnreadChangesetId({
    required String? username,
    required UploadMode uploadMode,
    bool forceRefresh = false,
  }) async {
    if (uploadMode == UploadMode.simulate) return null;
    if (username == null || username.isEmpty) return null;

    if (!forceRefresh &&
        _lastResultIsSet &&
        _lastMode == uploadMode &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _cacheDuration) {
      return _lastResult;
    }

    try {
      final current = await _fetchCommentCounts(username, uploadMode);
      if (current == null) return null;

      final seen = await _loadSeenCounts(uploadMode);
      // current is built from the API response, which is ordered
      // newest-first, so the first match found is the most recent one.
      int? unreadId;
      for (final entry in current.entries) {
        if (entry.value > (seen[entry.key] ?? 0)) {
          unreadId = entry.key;
          break;
        }
      }

      _lastCheck = DateTime.now();
      _lastResult = unreadId;
      _lastResultIsSet = true;
      _lastMode = uploadMode;

      return unreadId;
    } catch (e) {
      return null;
    }
  }

  /// Mark all currently-visible changeset comments as read by saving the
  /// current comment counts as the new baseline.
  Future<void> markRead({
    required String? username,
    required UploadMode uploadMode,
  }) async {
    if (uploadMode == UploadMode.simulate) return;
    if (username == null || username.isEmpty) return;

    try {
      final current = await _fetchCommentCounts(username, uploadMode);
      if (current == null) return;

      await _saveSeenCounts(uploadMode, current);

      // Update in-memory cache so getUnreadChangesetId() doesn't need to
      // re-fetch immediately after marking read.
      _lastCheck = DateTime.now();
      _lastResult = null;
      _lastResultIsSet = true;
      _lastMode = uploadMode;
    } catch (e) {
      // Best-effort - if this fails the badge will just persist until the
      // next successful mark-read attempt.
    }
  }

  /// Clear cached state (useful on logout or upload mode change).
  void clearCache() {
    _lastCheck = null;
    _lastResult = null;
    _lastResultIsSet = false;
    _lastMode = null;
  }

  /// Build the URL to the given changeset on the OSM website for the given
  /// upload mode.
  String getChangesetUrl(int changesetId, UploadMode uploadMode) {
    switch (uploadMode) {
      case UploadMode.production:
        return 'https://www.openstreetmap.org/changeset/$changesetId';
      case UploadMode.sandbox:
        return 'https://master.apis.dev.openstreetmap.org/changeset/$changesetId';
      case UploadMode.simulate:
        return 'https://www.openstreetmap.org/changeset/$changesetId';
    }
  }

  /// Fetches the user's most recent changesets and returns a map of
  /// changeset ID -> comments_count. Returns null on any error.
  Future<Map<int, int>?> _fetchCommentCounts(
    String username,
    UploadMode uploadMode,
  ) async {
    final apiHost = _getApiHost(uploadMode);
    final response = await _client.get(
      Uri.parse('$apiHost/api/0.6/changesets.json?display_name=${Uri.encodeQueryComponent(username)}'),
    );

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);
    final changesets = data['changesets'];
    if (changesets is! List) return null;

    final result = <int, int>{};
    for (final cs in changesets) {
      final id = cs['id'];
      final count = cs['comments_count'];
      if (id is int && count is int) {
        result[id] = count;
      }
    }
    return result;
  }

  Future<Map<int, int>> _loadSeenCounts(UploadMode uploadMode) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey(uploadMode));
    if (json == null) return {};
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(int.parse(k), v as int));
    } catch (e) {
      return {};
    }
  }

  Future<void> _saveSeenCounts(UploadMode uploadMode, Map<int, int> counts) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(counts.map((k, v) => MapEntry(k.toString(), v)));
    await prefs.setString(_prefsKey(uploadMode), encoded);
  }

  String _prefsKey(UploadMode uploadMode) =>
      'changeset_comments_seen_${uploadMode.name}';

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

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'version_service.dart';

/// Service for managing changelog data and first launch detection
class ChangelogService {
  static final ChangelogService _instance = ChangelogService._internal();
  factory ChangelogService() => _instance;
  ChangelogService._internal();

  static const String _lastSeenVersionKey = 'last_seen_version';
  static const String _hasSeenWelcomeKey = 'has_seen_welcome';

  Map<String, dynamic>? _changelogData;
  bool _initialized = false;

  /// Initialize the service by loading changelog data
  Future<void> init() async {
    if (_initialized) return;
    
    try {
      final String jsonString = await rootBundle.loadString('assets/changelog.json');
      _changelogData = json.decode(jsonString);
      _initialized = true;
      debugPrint('[ChangelogService] Loaded changelog with ${_changelogData?.keys.length ?? 0} versions');
    } catch (e) {
      debugPrint('[ChangelogService] Failed to load changelog: $e');
      _changelogData = {};
      _initialized = true; // Mark as initialized even on failure to prevent repeated attempts
    }
  }

  /// Check if this is the first app launch ever
  Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !prefs.containsKey(_lastSeenVersionKey);
  }

  /// Check if user has seen the welcome popup (separate from version tracking)
  Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenWelcomeKey) ?? false;
  }

  /// Mark that user has seen the welcome popup
  Future<void> markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenWelcomeKey, true);
  }

  /// Check if app version has changed since last launch
  Future<bool> hasVersionChanged() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenVersion = prefs.getString(_lastSeenVersionKey);
    final currentVersion = VersionService().version;
    
    return lastSeenVersion != currentVersion;
  }

  /// Update the stored version to current version
  Future<void> updateLastSeenVersion() async {
    final prefs = await SharedPreferences.getInstance();
    final currentVersion = VersionService().version;
    await prefs.setString(_lastSeenVersionKey, currentVersion);
    debugPrint('[ChangelogService] Updated last seen version to: $currentVersion');
  }

  /// Get changelog content for the current version
  String? getChangelogForCurrentVersion() {
    if (!_initialized || _changelogData == null) {
      debugPrint('[ChangelogService] Not initialized or no changelog data');
      return null;
    }

    final currentVersion = VersionService().version;
    final versionData = _changelogData![currentVersion] as Map<String, dynamic>?;
    
    if (versionData == null) {
      debugPrint('[ChangelogService] No changelog entry found for version: $currentVersion');
      return null;
    }

    final content = versionData['content'] as String?;
    return (content?.isEmpty == true) ? null : content;
  }

  /// Get changelog content for a specific version
  String? getChangelogForVersion(String version) {
    if (!_initialized || _changelogData == null) return null;
    
    final versionData = _changelogData![version] as Map<String, dynamic>?;
    if (versionData == null) return null;
    
    final content = versionData['content'] as String?;
    return (content?.isEmpty == true) ? null : content;
  }

  /// Get all changelog entries (for settings page)
  Map<String, String> getAllChangelogs() {
    if (!_initialized || _changelogData == null) return {};

    final Map<String, String> result = {};
    
    for (final entry in _changelogData!.entries) {
      final version = entry.key;
      final versionData = entry.value as Map<String, dynamic>?;
      final content = versionData?['content'] as String?;
      
      // Only include versions with non-empty content
      if (content != null && content.isNotEmpty) {
        result[version] = content;
      }
    }
    
    return result;
  }

  /// Determine what popup (if any) should be shown
  Future<PopupType> getPopupType() async {
    // Ensure services are initialized
    if (!_initialized) await init();

    final isFirstLaunch = await this.isFirstLaunch();
    final hasSeenWelcome = await this.hasSeenWelcome();
    final hasVersionChanged = await this.hasVersionChanged();

    // First launch and haven't seen welcome
    if (isFirstLaunch || !hasSeenWelcome) {
      return PopupType.welcome;
    }

    // Version changed and there's changelog content
    if (hasVersionChanged) {
      final changelogContent = getChangelogForCurrentVersion();
      if (changelogContent != null) {
        return PopupType.changelog;
      }
    }

    return PopupType.none;
  }

  /// Check if the service is properly initialized
  bool get isInitialized => _initialized;
}

/// Types of popups that can be shown
enum PopupType {
  none,
  welcome,
  changelog,
}
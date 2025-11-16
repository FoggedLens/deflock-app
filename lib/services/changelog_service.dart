import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'version_service.dart';
import '../app_state.dart';

/// Service for managing changelog data and first launch detection
class ChangelogService {
  static final ChangelogService _instance = ChangelogService._internal();
  factory ChangelogService() => _instance;
  ChangelogService._internal();

  static const String _lastSeenVersionKey = 'last_seen_version';
  static const String _hasSeenWelcomeKey = 'has_seen_welcome';

  Map<String, dynamic>? _changelogData;
  bool _initialized = false;

  /// Parse changelog content from either string or array format
  String? _parseChangelogContent(dynamic content) {
    if (content == null) return null;
    
    if (content is String) {
      // Legacy format: single string with \n
      return content.isEmpty ? null : content;
    } else if (content is List) {
      // New format: array of strings
      final lines = content.whereType<String>().where((line) => line.isNotEmpty).toList();
      return lines.isEmpty ? null : lines.join('\n');
    }
    
    return null;
  }

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

  /// Get the last seen version (for migration purposes)
  Future<String?> getLastSeenVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSeenVersionKey);
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

    return _parseChangelogContent(versionData['content']);
  }

  /// Get the changelog content that should be displayed (may be combined from multiple versions)
  /// This is the method home_screen should use to get content for the changelog popup
  Future<String?> getChangelogContentForDisplay() async {
    return await getCombinedChangelogContent();
  }

  /// Complete the version change workflow - call this after showing popups
  /// This updates the last seen version so migrations don't run again
  Future<void> completeVersionChange() async {
    await updateLastSeenVersion();
  }

  /// Get changelog content for a specific version
  String? getChangelogForVersion(String version) {
    if (!_initialized || _changelogData == null) return null;
    
    final versionData = _changelogData![version] as Map<String, dynamic>?;
    if (versionData == null) return null;
    
    return _parseChangelogContent(versionData['content']);
  }

  /// Get all changelog entries (for settings page)
  Map<String, String> getAllChangelogs() {
    if (!_initialized || _changelogData == null) return {};

    final Map<String, String> result = {};
    
    for (final entry in _changelogData!.entries) {
      final version = entry.key;
      final versionData = entry.value as Map<String, dynamic>?;
      final content = _parseChangelogContent(versionData?['content']);
      
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
      final changelogContent = await getCombinedChangelogContent();
      if (changelogContent != null) {
        return PopupType.changelog;
      }
    }

    return PopupType.none;
  }

  /// Check if version-change migrations need to be run
  /// Returns list of version strings that need migrations
  Future<List<String>> getVersionsNeedingMigration() async {
    final lastSeenVersion = await getLastSeenVersion();
    final currentVersion = VersionService().version;
    
    if (lastSeenVersion == null) return []; // First launch, no migrations needed
    
    final versionsNeedingMigration = <String>[];
    
    // Check each version that could need migration
    if (needsMigration(lastSeenVersion, currentVersion, '1.3.1')) {
      versionsNeedingMigration.add('1.3.1');
    }
    
    // Future versions can be added here
    // if (needsMigration(lastSeenVersion, currentVersion, '2.0.0')) {
    //   versionsNeedingMigration.add('2.0.0');
    // }
    
    return versionsNeedingMigration;
  }

  /// Get combined changelog content for all versions between last seen and current
  /// Returns null if no changelog content exists for any intermediate version
  Future<String?> getCombinedChangelogContent() async {
    if (!_initialized || _changelogData == null) return null;
    
    final lastSeenVersion = await getLastSeenVersion();
    final currentVersion = VersionService().version;
    
    if (lastSeenVersion == null) {
      // First launch - just return current version changelog
      return getChangelogForCurrentVersion();
    }
    
    final intermediateVersions = <String>[];
    
    // Collect all relevant versions between lastSeen and current (exclusive of lastSeen, inclusive of current)
    for (final entry in _changelogData!.entries) {
      final version = entry.key;
      final versionData = entry.value as Map<String, dynamic>?;
      final content = _parseChangelogContent(versionData?['content']);
      
      // Skip versions with empty content
      if (content == null || content.isEmpty) continue;
      
      // Include versions where: lastSeenVersion < version <= currentVersion
      if (needsMigration(lastSeenVersion, currentVersion, version)) {
        intermediateVersions.add(version);
      }
    }
    
    // Sort versions in descending order (newest first)
    intermediateVersions.sort((a, b) => compareVersions(b, a));
    
    // Build changelog content
    final intermediateChangelogs = intermediateVersions.map((version) {
      final versionData = _changelogData![version] as Map<String, dynamic>;
      final content = _parseChangelogContent(versionData['content'])!; // Safe to use ! here since we filtered empty content above
      return '**Version $version:**\n$content';
    }).toList();
    
    return intermediateChangelogs.isNotEmpty ? intermediateChangelogs.join('\n\n---\n\n') : null;
  }

  /// Check if the service is properly initialized
  bool get isInitialized => _initialized;

  /// Run a specific migration by version number
  Future<void> runMigration(String version, AppState appState) async {
    debugPrint('[ChangelogService] Running $version migration');
    
    switch (version) {
      case '1.3.1':
        // Enable network status indicator for all existing users
        await appState.setNetworkStatusIndicatorEnabled(true);
        debugPrint('[ChangelogService] 1.3.1 migration completed: enabled network status indicator');
        break;
        
      // Future migrations can be added here
      // case '2.0.0':
      //   await appState.doSomethingNew();
      //   debugPrint('[ChangelogService] 2.0.0 migration completed');
      //   break;
      
      default:
        debugPrint('[ChangelogService] Unknown migration version: $version');
    }
  }

  /// Check if a migration should run
  /// Migration runs if: lastSeenVersion < migrationVersion <= currentVersion
  bool needsMigration(String lastSeenVersion, String currentVersion, String migrationVersion) {
    final lastVsMigration = compareVersions(lastSeenVersion, migrationVersion);
    final migrationVsCurrent = compareVersions(migrationVersion, currentVersion);
    
    return lastVsMigration < 0 && migrationVsCurrent <= 0;
  }

  /// Compare two version strings
  /// Returns -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2
  /// Versions are expected in format "major.minor.patch" (e.g., "1.3.1")
  int compareVersions(String v1, String v2) {
    try {
      final v1Parts = v1.split('.').map(int.parse).toList();
      final v2Parts = v2.split('.').map(int.parse).toList();
      
      // Ensure we have at least 3 parts (major.minor.patch)
      while (v1Parts.length < 3) v1Parts.add(0);
      while (v2Parts.length < 3) v2Parts.add(0);
      
      // Compare major version first
      if (v1Parts[0] < v2Parts[0]) return -1;
      if (v1Parts[0] > v2Parts[0]) return 1;
      
      // Major versions equal, compare minor version
      if (v1Parts[1] < v2Parts[1]) return -1;
      if (v1Parts[1] > v2Parts[1]) return 1;
      
      // Major and minor equal, compare patch version
      if (v1Parts[2] < v2Parts[2]) return -1;
      if (v1Parts[2] > v2Parts[2]) return 1;
      
      // All parts equal
      return 0;
      
    } catch (e) {
      debugPrint('[ChangelogService] Error comparing versions "$v1" vs "$v2": $e');
      // Safe fallback: assume they're different so we run migrations
      return v1 == v2 ? 0 : -1;
    }
  }
}

/// Types of popups that can be shown
enum PopupType {
  none,
  welcome,
  changelog,
}
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'services/profile_service.dart';
import 'services/suspected_location_cache.dart';
import 'widgets/nuclear_reset_dialog.dart';

/// One-time migrations that run when users upgrade to specific versions.
/// Each migration function is named after the version where it should run.
class OneTimeMigrations {
  /// Enable network status indicator for all existing users (v1.3.1)
  static Future<void> migrate_1_3_1(AppState appState) async {
    await appState.setNetworkStatusIndicatorEnabled(true);
    debugPrint('[Migration] 1.3.1 completed: enabled network status indicator');
  }

  /// Migrate upload queue to new two-stage changeset system (v1.5.3)
  static Future<void> migrate_1_5_3(AppState appState) async {
    // Migration is handled automatically in PendingUpload.fromJson via _migrateFromLegacyFields
    // This triggers a queue reload to apply migrations
    await appState.reloadUploadQueue();
    debugPrint('[Migration] 1.5.3 completed: migrated upload queue to two-stage system');
  }

  /// Clear FOV values from built-in profiles only (v1.6.3)
  static Future<void> migrate_1_6_3(AppState appState) async {
    // Load all custom profiles from storage (includes any customized built-in profiles)
    final profiles = await ProfileService().load();
    
    // Find profiles with built-in IDs and clear their FOV values
    final updatedProfiles = profiles.map((profile) {
      if (profile.id.startsWith('builtin-') && profile.fov != null) {
        debugPrint('[Migration] Clearing FOV from profile: ${profile.id}');
        return profile.copyWith(fov: null);
      }
      return profile;
    }).toList();
    
    // Save updated profiles back to storage
    await ProfileService().save(updatedProfiles);
    
    debugPrint('[Migration] 1.6.3 completed: cleared FOV values from built-in profiles');
  }

  /// Migrate suspected locations from SharedPreferences to SQLite (v1.8.0)
  static Future<void> migrate_1_8_0(AppState appState) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Legacy SharedPreferences keys
      const legacyProcessedDataKey = 'suspected_locations_processed_data';
      const legacyLastFetchKey = 'suspected_locations_last_fetch';
      
      // Check if we have legacy data
      final legacyData = prefs.getString(legacyProcessedDataKey);
      final legacyLastFetch = prefs.getInt(legacyLastFetchKey);
      
      if (legacyData != null && legacyLastFetch != null) {
        debugPrint('[Migration] 1.8.0: Found legacy suspected location data, migrating to database...');
        
        // Parse legacy processed data format
        final List<dynamic> legacyProcessedList = jsonDecode(legacyData);
        final List<Map<String, dynamic>> rawDataList = [];
        
        for (final entry in legacyProcessedList) {
          if (entry is Map<String, dynamic> && entry['rawData'] != null) {
            rawDataList.add(Map<String, dynamic>.from(entry['rawData']));
          }
        }
        
        if (rawDataList.isNotEmpty) {
          final fetchTime = DateTime.fromMillisecondsSinceEpoch(legacyLastFetch);
          
          // Get the cache instance and migrate data
          final cache = SuspectedLocationCache();
          await cache.loadFromStorage(); // Initialize database
          await cache.processAndSave(rawDataList, fetchTime);
          
          debugPrint('[Migration] 1.8.0: Migrated ${rawDataList.length} entries from legacy storage');
        }
        
        // Clean up legacy data after successful migration
        await prefs.remove(legacyProcessedDataKey);
        await prefs.remove(legacyLastFetchKey);
        
        debugPrint('[Migration] 1.8.0: Legacy data cleanup completed');
      }
      
      // Ensure suspected locations are reinitialized with new system
      await appState.reinitSuspectedLocations();
      
      debugPrint('[Migration] 1.8.0 completed: migrated suspected locations to SQLite database');
    } catch (e) {
      debugPrint('[Migration] 1.8.0 ERROR: Failed to migrate suspected locations: $e');
      // Don't rethrow - migration failure shouldn't break the app
      // The new system will work fine, users just lose their cached data
    }
  }

  /// Clear any active sessions to reset refined tags system (v2.1.0)
  static Future<void> migrate_2_1_0(AppState appState) async {
    try {
      // Clear any existing sessions since they won't have refinedTags field
      // This is simpler and safer than trying to migrate session data
      appState.cancelSession();
      appState.cancelEditSession();
      
      debugPrint('[Migration] 2.1.0 completed: cleared sessions for refined tags system');
    } catch (e) {
      debugPrint('[Migration] 2.1.0 ERROR: Failed to clear sessions: $e');
      // Don't rethrow - this is non-critical
    }
  }

  /// Get the migration function for a specific version
  static Future<void> Function(AppState)? getMigrationForVersion(String version) {
    switch (version) {
      case '1.3.1':
        return migrate_1_3_1;
      case '1.5.3':
        return migrate_1_5_3;
      case '1.6.3':
        return migrate_1_6_3;
      case '1.8.0':
        return migrate_1_8_0;
      case '2.1.0':
        return migrate_2_1_0;
      default:
        return null;
    }
  }

  /// Run migration for a specific version with nuclear reset on failure
  static Future<void> runMigration(String version, AppState appState, BuildContext? context) async {
    try {
      final migration = getMigrationForVersion(version);
      if (migration != null) {
        await migration(appState);
      } else {
        debugPrint('[Migration] Unknown migration version: $version');
      }
    } catch (error, stackTrace) {
      debugPrint('[Migration] CRITICAL: Migration $version failed: $error');
      debugPrint('[Migration] Stack trace: $stackTrace');
      
      // Nuclear option: clear everything and show non-dismissible error dialog
      if (context != null) {
        NuclearResetDialog.show(context, error, stackTrace);
      } else {
        // If no context available, just log and hope for the best
        debugPrint('[Migration] No context available for error dialog, migration failure unhandled');
      }
    }
  }
}
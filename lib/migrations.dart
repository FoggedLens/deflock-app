import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'services/profile_service.dart';
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

  /// Get the migration function for a specific version
  static Future<void> Function(AppState)? getMigrationForVersion(String version) {
    switch (version) {
      case '1.3.1':
        return migrate_1_3_1;
      case '1.5.3':
        return migrate_1_5_3;
      case '1.6.3':
        return migrate_1_6_3;
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
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'version_service.dart';

/// Nuclear reset service - clears ALL app data when migrations fail.
/// This is the "big hammer" approach for when something goes seriously wrong.
class NuclearResetService {
  static final NuclearResetService _instance = NuclearResetService._();
  factory NuclearResetService() => _instance;
  NuclearResetService._();

  /// Completely clear all app data - SharedPreferences, files, caches, everything.
  /// After this, the app should behave exactly like a fresh install.
  static Future<void> clearEverything() async {
    try {
      debugPrint('[NuclearReset] Starting complete app data wipe...');

      // Clear ALL SharedPreferences
      await _clearSharedPreferences();

      // Clear ALL files in app directories
      await _clearFileSystem();

      debugPrint('[NuclearReset] Complete app data wipe finished');
    } catch (e) {
      // Even the nuclear option can fail, but we can't do anything about it
      debugPrint('[NuclearReset] Error during nuclear reset: $e');
    }
  }

  /// Clear all SharedPreferences data
  static Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('[NuclearReset] Cleared SharedPreferences');
    } catch (e) {
      debugPrint('[NuclearReset] Failed to clear SharedPreferences: $e');
    }
  }

  /// Clear all files and directories in app storage
  static Future<void> _clearFileSystem() async {
    try {
      // Clear Documents directory (offline areas, etc.)
      await _clearDirectory(() => getApplicationDocumentsDirectory(), 'Documents');
      
      // Clear Cache directory (tile cache, etc.)
      await _clearDirectory(() => getTemporaryDirectory(), 'Cache');
      
      // Clear Support directory if it exists (iOS/macOS)
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        await _clearDirectory(() => getApplicationSupportDirectory(), 'Support');
      }
      
    } catch (e) {
      debugPrint('[NuclearReset] Failed to clear file system: $e');
    }
  }

  /// Clear a specific directory, with error handling
  static Future<void> _clearDirectory(
    Future<Directory> Function() getDirFunc,
    String dirName,
  ) async {
    try {
      final dir = await getDirFunc();
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
        debugPrint('[NuclearReset] Cleared $dirName directory');
      }
    } catch (e) {
      debugPrint('[NuclearReset] Failed to clear $dirName directory: $e');
    }
  }

  /// Generate error report information (safely, with fallbacks)
  static Future<String> generateErrorReport(Object error, StackTrace? stackTrace) async {
    final buffer = StringBuffer();
    
    // Basic error information (always include this)
    buffer.writeln('MIGRATION FAILURE ERROR REPORT');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');
    buffer.writeln('Error: $error');
    
    if (stackTrace != null) {
      buffer.writeln('');
      buffer.writeln('Stack trace:');
      buffer.writeln(stackTrace.toString());
    }
    
    // Try to add enrichment data, but don't fail if it doesn't work
    await _addEnrichmentData(buffer);
    
    return buffer.toString();
  }

  /// Add device/app information to error report (with extensive error handling)
  static Future<void> _addEnrichmentData(StringBuffer buffer) async {
    try {
      buffer.writeln('');
      buffer.writeln('--- System Information ---');
      
      // App version (should always work)
      try {
        buffer.writeln('App Version: ${VersionService().version}');
      } catch (e) {
        buffer.writeln('App Version: [Failed to get version: $e]');
      }
      
      // Platform information
      try {
        if (!kIsWeb) {
          buffer.writeln('Platform: ${Platform.operatingSystem}');
          buffer.writeln('OS Version: ${Platform.operatingSystemVersion}');
        } else {
          buffer.writeln('Platform: Web');
        }
      } catch (e) {
        buffer.writeln('Platform: [Failed to get platform info: $e]');
      }
      
      // Flutter/Dart information
      try {
        buffer.writeln('Flutter Mode: ${kDebugMode ? 'Debug' : kProfileMode ? 'Profile' : 'Release'}');
      } catch (e) {
        buffer.writeln('Flutter Mode: [Failed to get mode: $e]');
      }
      
      // Previous version (if available)
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastVersion = prefs.getString('last_seen_version');
        buffer.writeln('Previous Version: ${lastVersion ?? 'Unknown (fresh install?)'}');
      } catch (e) {
        buffer.writeln('Previous Version: [Failed to get: $e]');
      }
      
    } catch (e) {
      // If enrichment completely fails, just note it
      buffer.writeln('');
      buffer.writeln('--- System Information ---');
      buffer.writeln('[Failed to gather system information: $e]');
    }
  }

  /// Copy text to clipboard (safely)
  static Future<void> copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      debugPrint('[NuclearReset] Copied error report to clipboard');
    } catch (e) {
      debugPrint('[NuclearReset] Failed to copy to clipboard: $e');
    }
  }
}
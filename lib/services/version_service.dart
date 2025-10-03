import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Service for getting app version information from pubspec.yaml.
/// This ensures we have a single source of truth for version info.
class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  PackageInfo? _packageInfo;
  bool _initialized = false;

  /// Initialize the service by loading package info
  Future<void> init() async {
    if (_initialized) return;
    
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      _initialized = true;
      debugPrint('[VersionService] Loaded version: ${_packageInfo!.version}');
    } catch (e) {
      debugPrint('[VersionService] Failed to load package info: $e');
      _initialized = false;
    }
  }

  /// Get the app version (e.g., "1.0.2")
  String get version {
    if (!_initialized || _packageInfo == null) {
      debugPrint('[VersionService] Warning: Service not initialized, returning fallback version');
      return 'unknown'; // Fallback for development/testing
    }
    return _packageInfo!.version;
  }

  /// Get the app name
  String get appName {
    if (!_initialized || _packageInfo == null) {
      return 'DeFlock'; // Fallback
    }
    return _packageInfo!.appName;
  }

  /// Get the package name/bundle ID
  String get packageName {
    if (!_initialized || _packageInfo == null) {
      return 'me.deflock.deflockapp'; // Fallback
    }
    return _packageInfo!.packageName;
  }

  /// Get the build number
  String get buildNumber {
    if (!_initialized || _packageInfo == null) {
      return '1'; // Fallback
    }
    return _packageInfo!.buildNumber;
  }

  /// Get full version string with build number (e.g., "1.0.2+1")
  String get fullVersion {
    return '$version+$buildNumber';
  }

  /// Check if the service is properly initialized
  bool get isInitialized => _initialized && _packageInfo != null;
}
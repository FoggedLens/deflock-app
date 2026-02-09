import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../models/node_profile.dart';
import 'profile_import_service.dart';
import '../screens/profile_editor.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  
  /// Initialize deep link handling (sets up stream listener only)
  Future<void> init() async {
    _appLinks = AppLinks();
    
    // Set up stream listener for links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _processLink,
      onError: (err) {
        debugPrint('[DeepLinkService] Link stream error: $err');
      },
    );
  }
  
  /// Process a deep link
  void _processLink(Uri uri) {
    debugPrint('[DeepLinkService] Processing deep link: $uri');
    
    // Only handle deflockapp scheme
    if (uri.scheme != 'deflockapp') {
      debugPrint('[DeepLinkService] Ignoring non-deflockapp scheme: ${uri.scheme}');
      return;
    }
    
    // Route based on path
    switch (uri.host) {
      case 'profiles':
        _handleProfilesLink(uri);
        break;
      case 'auth':
        // OAuth links are handled by flutter_web_auth_2
        debugPrint('[DeepLinkService] OAuth link handled by flutter_web_auth_2');
        break;
      default:
        debugPrint('[DeepLinkService] Unknown deep link host: ${uri.host}');
    }
  }
  
  /// Check for initial link after app is fully ready
  Future<void> checkInitialLink() async {
    debugPrint('[DeepLinkService] Checking for initial link...');
    
    try {
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('[DeepLinkService] Found initial link: $initialLink');
        _processLink(initialLink);
      } else {
        debugPrint('[DeepLinkService] No initial link found');
      }
    } catch (e) {
      debugPrint('[DeepLinkService] Failed to get initial link: $e');
    }
  }
  
  /// Handle profile-related deep links
  void _handleProfilesLink(Uri uri) {
    final segments = uri.pathSegments;
    
    if (segments.isEmpty) {
      debugPrint('[DeepLinkService] No path segments in profiles link');
      return;
    }
    
    switch (segments[0]) {
      case 'add':
        _handleAddProfileLink(uri);
        break;
      default:
        debugPrint('[DeepLinkService] Unknown profiles path: ${segments[0]}');
    }
  }
  
  /// Handle profile add deep link: `deflockapp://profiles/add?p=<base64>`
  void _handleAddProfileLink(Uri uri) {
    final base64Data = uri.queryParameters['p'];
    
    if (base64Data == null || base64Data.isEmpty) {
      _showError('Invalid profile link: missing profile data');
      return;
    }
    
    // Parse profile from base64
    final profile = ProfileImportService.parseProfileFromBase64(base64Data);
    
    if (profile == null) {
      _showError('Invalid profile data');
      return;
    }
    
    // Navigate to profile editor with the imported profile
    _navigateToProfileEditor(profile);
  }
  
  /// Navigate to profile editor with pre-filled profile data
  void _navigateToProfileEditor(NodeProfile profile) {
    final context = _navigatorKey?.currentContext;
    
    if (context == null) {
      debugPrint('[DeepLinkService] No navigator context available');
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileEditor(profile: profile),
      ),
    );
  }
  
  /// Show error message to user
  void _showError(String message) {
    final context = _navigatorKey?.currentContext;
    
    if (context == null) {
      debugPrint('[DeepLinkService] Error (no context): $message');
      return;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
  
  /// Global navigator key for navigation
  GlobalKey<NavigatorState>? _navigatorKey;
  
  /// Set the global navigator key
  void setNavigatorKey(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
  }
  
  /// Clean up resources
  void dispose() {
    _linkSubscription?.cancel();
  }
}
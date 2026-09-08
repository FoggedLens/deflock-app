import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/osm_node.dart';
import '../models/node_profile.dart';
import '../dev_config.dart';

/// Simple data class for tracking recent proximity alerts to prevent spam
class RecentAlert {
  final int nodeId;
  final DateTime alertTime;

  RecentAlert({required this.nodeId, required this.alertTime});
}

/// Service for handling proximity alerts when approaching surveillance nodes
/// Follows brutalist principles: simple, explicit, easy to understand
class ProximityAlertService {
  static final ProximityAlertService _instance = ProximityAlertService._internal();
  factory ProximityAlertService() => _instance;
  ProximityAlertService._internal();

  FlutterLocalNotificationsPlugin? _notifications;

  /// Whether the plugin itself is usable. Deliberately NOT derived from
  /// initialize()'s return value: on iOS that reports the outcome of the
  /// permission request, which we intentionally disable below, so it returns
  /// false even though the plugin works fine. Gating on it made every
  /// notification path dead on iOS.
  bool _pluginReady = false;

  /// Guards against re-initializing on every settings visit.
  Future<void>? _initFuture;

  // Simple in-memory tracking of recent alerts to prevent spam
  final List<RecentAlert> _recentAlerts = [];
  static const Duration _alertCooldown = kProximityAlertCooldown;

  // Callback for showing in-app visual alerts
  VoidCallback? _onVisualAlert;

  /// Initialize the notification plugin. Permissions are requested separately,
  /// on demand, when the user enables proximity alerts.
  Future<void> initialize({VoidCallback? onVisualAlert}) {
    if (onVisualAlert != null) _onVisualAlert = onVisualAlert;
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    _notifications = FlutterLocalNotificationsPlugin();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _notifications!.initialize(initSettings);
      // Completing without throwing is the real signal that the plugin is up.
      _pluginReady = true;
      debugPrint('[ProximityAlertService] Plugin ready (permissions deferred)');
    } catch (e) {
      debugPrint('[ProximityAlertService] Failed to initialize: $e');
      _pluginReady = false;
      _initFuture = null; // Allow a later retry
    }
  }

  /// Ensure the plugin is up before touching it, so callers that arrive before
  /// MapView's fire-and-forget initialize() completes still work.
  Future<bool> _ensureReady() async {
    if (_pluginReady) return true;
    await initialize();
    return _pluginReady;
  }
  
  /// Request notification permissions on both platforms.
  ///
  /// Note that on iOS the system prompt appears only ONCE, ever. After the
  /// user has answered it, this call returns silently without showing
  /// anything — which is why callers must check the result and fall back to
  /// sending the user to system settings.
  Future<void> _requestNotificationPermissions() async {
    if (_notifications == null) return;

    try {
      final android = _notifications!
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final result = await android.requestNotificationsPermission();
        debugPrint('[ProximityAlertService] Android permission result: $result');
        return;
      }

      final ios = _notifications!
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final result = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('[ProximityAlertService] iOS permission result: $result');
      }
    } catch (e) {
      debugPrint('[ProximityAlertService] Failed to request permissions: $e');
    }
  }

  /// Open the OS settings page for this app, so the user can grant
  /// notifications after the one-shot iOS prompt has already been answered.
  /// Uses Geolocator's platform channel purely as a way to open app settings;
  /// it is not location-specific.
  Future<bool> openSystemSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('[ProximityAlertService] Failed to open app settings: $e');
      return false;
    }
  }
  
  /// Check proximity to nodes and trigger alerts if needed.
  /// This should be called on GPS position updates.
  Future<void> checkProximity({
    required LatLng userLocation,
    required List<OsmNode> nodes,
    required List<NodeProfile> enabledProfiles,
    required int alertDistance,
  }) async {
    if (!_pluginReady || nodes.isEmpty) return;

    // Clean up old alerts (anything older than cooldown period)
    final cutoffTime = DateTime.now().subtract(_alertCooldown);
    _recentAlerts.removeWhere((alert) => alert.alertTime.isBefore(cutoffTime));

    // Check each node for proximity
    for (final node in nodes) {
      // Skip if we recently alerted for this node
      if (_recentAlerts.any((alert) => alert.nodeId == node.id)) continue;

      final distance = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        node.coord.latitude,
        node.coord.longitude,
      );

      if (distance <= alertDistance) {
        final nodeType = _getNodeTypeDescription(node, enabledProfiles);

        await _showNotification(node, nodeType, distance.round());
        _showVisualAlert();

        _recentAlerts.add(RecentAlert(nodeId: node.id, alertTime: DateTime.now()));

        debugPrint('[ProximityAlertService] Alert triggered for node ${node.id} ($nodeType) at ${distance.round()}m');
      }
    }
  }

  /// Notification IDs must fit in a signed 32-bit int, but OSM node IDs are
  /// well past that (currently ~12 billion), so passing one through raises
  /// "must fit within the size of a 32-bit integer" and the notification is
  /// dropped. Fold to a stable positive 31-bit value instead.
  ///
  /// Deterministic across runs, so re-alerting for the same node replaces the
  /// existing notification rather than stacking a duplicate.
  static int _notificationId(int nodeId) => nodeId.abs() % 0x7FFFFFFF;

  /// Show push notification for proximity alert
  Future<void> _showNotification(OsmNode node, String nodeType, int distance) async {
    await _show(
      id: _notificationId(node.id),
      title: 'Surveillance Device Nearby',
      body: '$nodeType detected ${distance}m ahead',
    );
  }

  Future<void> _show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_pluginReady || _notifications == null) {
      debugPrint('[ProximityAlertService] NOT SHOWN: plugin not ready');
      return;
    }

    // A notification that silently no-ops because permission was never granted
    // is indistinguishable from one that was never triggered. Say which.
    if (!await areNotificationsEnabled()) {
      debugPrint(
        '[ProximityAlertService] NOT SHOWN: OS notification permission not '
        'granted. Settings → Proximity Alerts → Enable Notifications.',
      );
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'proximity_alerts',
      'Proximity Alerts',
      channelDescription: 'Notifications when approaching surveillance devices',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    
    const iosDetails = DarwinNotificationDetails(
      // presentAlert is dead on iOS 14+: the plugin's willPresentNotification
      // only consults presentBanner/presentList there and ignores presentAlert
      // entirely. Setting just presentAlert produced no visible banner at all.
      // Keep it for iOS 13 and below, but presentBanner is what actually works.
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: false,
      presentSound: true,
    );
    
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    try {
      await _notifications!.show(
        id, // Use node ID as notification ID
        title,
        body,
        notificationDetails,
      );
      debugPrint('[ProximityAlertService] SHOWN id=$id "$title" — $body');
    } on ArgumentError catch (e) {
      debugPrint('[ProximityAlertService] Rejected notification id=$id: $e');
    } catch (e) {
      debugPrint('[ProximityAlertService] Failed to show notification: $e');
    }
  }
  
  /// Trigger visual alert in the app UI
  void _showVisualAlert() {
    _onVisualAlert?.call();
  }
  
  /// Get a user-friendly description of the node type
  String _getNodeTypeDescription(OsmNode node, List<NodeProfile> enabledProfiles) {
    final tags = node.tags;
    
    // Check for specific surveillance types
    if (tags.containsKey('man_made') && tags['man_made'] == 'surveillance') {
      final surveillanceType = tags['surveillance:type'] ?? 'surveillance device';
      if (surveillanceType == 'camera') return 'Camera';
      if (surveillanceType == 'ALPR') return 'License plate reader';
      return 'Surveillance device';
    }
    
    // Check for emergency devices
    if (tags.containsKey('emergency') && tags['emergency'] == 'siren') {
      return 'Emergency siren';
    }
    
    // Fall back to checking enabled profiles to see what type this might be
    for (final profile in enabledProfiles) {
      bool matches = true;
      for (final entry in profile.tags.entries) {
        if (node.tags[entry.key] != entry.value) {
          matches = false;
          break;
        }
      }
      if (matches) {
        return profile.name;
      }
    }
    
    return 'Surveillance device';
  }
  
  /// Get count of recent alerts (for debugging/testing)
  int get recentAlertCount => _recentAlerts.length;
  
  /// Clear recent alerts (for testing)
  void clearRecentAlerts() {
    _recentAlerts.clear();
  }
  
  /// Check if notification permissions are granted.
  Future<bool> areNotificationsEnabled() async {
    if (!await _ensureReady() || _notifications == null) return false;

    try {
      final androidImpl = _notifications!
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        final result = await androidImpl.areNotificationsEnabled();
        return result ?? false;
      }

      // iOS: actually ask the system rather than assuming. The old code
      // returned a blind `true` here, so the UI could never tell whether
      // notifications were really authorized.
      final iosImpl = _notifications!
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (iosImpl != null) {
        final options = await iosImpl.checkPermissions();
        if (options == null) return false;
        return options.isEnabled || options.isProvisionalEnabled;
      }

      return false;
    } catch (e) {
      debugPrint('[ProximityAlertService] Failed to check notification permissions: $e');
      return false;
    }
  }

  /// Request permissions and report whether they ended up granted.
  ///
  /// A `false` result does NOT mean the prompt was declined just now — on iOS
  /// the prompt may not have appeared at all because it was already answered
  /// in a previous launch. Callers should offer [openSystemSettings] on false.
  Future<bool> requestNotificationPermissions() async {
    if (!await _ensureReady()) return false;
    await _requestNotificationPermissions();
    final enabled = await areNotificationsEnabled();
    debugPrint('[ProximityAlertService] Permissions after request: $enabled');
    return enabled;
  }
}
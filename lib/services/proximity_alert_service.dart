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
  bool _isInitialized = false;
  
  // Simple in-memory tracking of recent alerts to prevent spam
  final List<RecentAlert> _recentAlerts = [];
  static const Duration _alertCooldown = kProximityAlertCooldown;
  
  // Callback for showing in-app visual alerts
  VoidCallback? _onVisualAlert;
  
  /// Initialize the notification plugin
  Future<void> initialize({VoidCallback? onVisualAlert}) async {
    _onVisualAlert = onVisualAlert;
    
    _notifications = FlutterLocalNotificationsPlugin();
    
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    try {
      final initialized = await _notifications!.initialize(initSettings);
      _isInitialized = initialized ?? false;
      debugPrint('[ProximityAlertService] Initialized: $_isInitialized');
    } catch (e) {
      debugPrint('[ProximityAlertService] Failed to initialize: $e');
      _isInitialized = false;
    }
  }
  
  /// Check proximity to nodes and trigger alerts if needed
  /// This should be called on GPS position updates
  Future<void> checkProximity({
    required LatLng userLocation,
    required List<OsmNode> nodes,
    required List<NodeProfile> enabledProfiles,
    required int alertDistance,
  }) async {
    if (!_isInitialized || nodes.isEmpty) return;
    
    // Clean up old alerts (anything older than cooldown period)
    final cutoffTime = DateTime.now().subtract(_alertCooldown);
    _recentAlerts.removeWhere((alert) => alert.alertTime.isBefore(cutoffTime));
    
    // Check each node for proximity
    for (final node in nodes) {
      // Skip if we recently alerted for this node
      if (_recentAlerts.any((alert) => alert.nodeId == node.id)) {
        continue;
      }
      
      // Calculate distance using Geolocator's distanceBetween
      final distance = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        node.coord.latitude,
        node.coord.longitude,
      );
      
      // Check if within alert distance
      if (distance <= alertDistance) {
        // Determine node type for alert message
        final nodeType = _getNodeTypeDescription(node, enabledProfiles);
        
        // Trigger both push notification and visual alert
        await _showNotification(node, nodeType, distance.round());
        _showVisualAlert();
        
        // Track this alert to prevent spam
        _recentAlerts.add(RecentAlert(
          nodeId: node.id,
          alertTime: DateTime.now(),
        ));
        
        debugPrint('[ProximityAlertService] Alert triggered for node ${node.id} ($nodeType) at ${distance.round()}m');
      }
    }
  }
  
  /// Show push notification for proximity alert
  Future<void> _showNotification(OsmNode node, String nodeType, int distance) async {
    if (!_isInitialized || _notifications == null) return;
    
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
      presentAlert: true,
      presentBadge: false,
      presentSound: true,
    );
    
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    final title = 'Surveillance Device Nearby';
    final body = '$nodeType detected ${distance}m ahead';
    
    try {
      await _notifications!.show(
        node.id, // Use node ID as notification ID
        title,
        body,
        notificationDetails,
      );
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
}
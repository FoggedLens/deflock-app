import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/rf_detection.dart';
import '../services/rf_detection_database.dart';
import '../services/usb_scanner_service.dart';

/// State module for the RF scanner (11th AppState module).
/// Manages USB scanner connection, detection processing, and map data.
class ScannerState extends ChangeNotifier {
  final UsbScannerService _scanner;
  final RfDetectionDatabase _db;

  ScannerState({UsbScannerService? scanner, RfDetectionDatabase? db})
      : _scanner = scanner ?? UsbScannerService(),
        _db = db ?? RfDetectionDatabase();

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<ScannerConnectionStatus>? _statusSubscription;

  ScannerConnectionStatus _connectionStatus =
      ScannerConnectionStatus.disconnected;
  final List<RfDetection> _recentDetections = [];
  int _detectionCount = 0;
  LatLng? _currentGpsPosition;
  double? _currentGpsAccuracy;

  static const int _maxRecentDetections = 50;

  // Public getters
  ScannerConnectionStatus get connectionStatus => _connectionStatus;
  List<RfDetection> get recentDetections =>
      List.unmodifiable(_recentDetections);
  int get detectionCount => _detectionCount;
  bool get isConnected => _scanner.isConnected;
  String? get lastError => _scanner.lastError;

  /// Initialize scanner: open database, start listening for USB device.
  Future<void> init() async {
    await _db.init();

    // Load initial detection count
    final stats = await _db.getStats();
    _detectionCount = stats['total'] as int;

    // Listen to scanner status changes
    _statusSubscription = _scanner.statusStream.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    // Listen to detection events
    _eventSubscription = _scanner.events.listen(_onSerialEvent);

    // Start USB listener
    await _scanner.init();

    notifyListeners();
  }

  /// Manually trigger a reconnect attempt.
  Future<bool> reconnect() async {
    return await _scanner.connect();
  }

  /// Disconnect from the USB scanner.
  Future<void> disconnect() async {
    await _scanner.disconnect();
  }

  /// Process an incoming detection event from the M5StickC.
  Future<void> _onSerialEvent(Map<String, dynamic> json) async {
    try {
      // Get current GPS position
      await _updateGpsPosition();

      if (_currentGpsPosition == null) {
        debugPrint('[ScannerState] Skipping detection — no GPS fix');
        return;
      }

      final now = DateTime.now();

      // Create detection and sighting from serial JSON
      final detection = RfDetection.fromSerialJson(
        json,
        _currentGpsPosition!,
        now,
      );

      final sighting = RfSighting.fromSerialJson(
        json,
        _currentGpsPosition!,
        _currentGpsAccuracy,
        now,
      );

      // Persist to database
      await _db.upsertDetection(detection);
      await _db.addSighting(sighting);

      // Update recent detections list
      _recentDetections.insert(0, detection);
      if (_recentDetections.length > _maxRecentDetections) {
        _recentDetections.removeLast();
      }

      _detectionCount++;
      notifyListeners();
    } catch (e) {
      debugPrint('[ScannerState] Error processing detection: $e');
    }
  }

  /// Update cached GPS position from the device.
  Future<void> _updateGpsPosition() async {
    try {
      final position = await getLastKnownPosition();
      if (position != null) {
        _currentGpsPosition = LatLng(position.latitude, position.longitude);
        _currentGpsAccuracy = position.accuracy;
      }
    } catch (e) {
      // GPS not available — keep last known position
    }
  }

  /// Wraps Geolocator call so tests can override without hardware.
  @visibleForTesting
  Future<Position?> getLastKnownPosition() async {
    return Geolocator.getLastKnownPosition();
  }

  /// Get detections within map bounds (for marker layer).
  Future<List<RfDetection>> getDetectionsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    return _db.getDetectionsInBounds(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  /// Get all detections with optional filters.
  Future<List<RfDetection>> getDetections({
    int? minAlertLevel,
    bool? hasOsmNode,
    int? limit,
  }) async {
    return _db.getDetections(
      minAlertLevel: minAlertLevel,
      hasOsmNode: hasOsmNode,
      limit: limit,
    );
  }

  /// Get sightings for a specific device.
  Future<List<RfSighting>> getSightingsForMac(String mac) async {
    return _db.getSightingsForMac(mac);
  }

  /// Link a detection to a successfully uploaded OSM node.
  Future<void> linkDetectionToNode(String mac, int osmNodeId) async {
    await _db.linkToOsmNode(mac, osmNodeId);
    notifyListeners();
  }

  /// Delete a detection and its sightings.
  Future<void> deleteDetection(String mac) async {
    await _db.deleteDetection(mac);
    _recentDetections.removeWhere((d) => d.mac == mac);
    _detectionCount--;
    notifyListeners();
  }

  /// Get aggregate statistics.
  Future<Map<String, dynamic>> getStats() async {
    return _db.getStats();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _statusSubscription?.cancel();
    // dispose() is async but ChangeNotifier.dispose() is not — fire and forget
    _scanner.dispose();
    _db.close();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../models/rf_detection.dart';
import '../services/rf_detection_database.dart';
import '../services/scanner_service.dart';
import '../services/ble_scanner_service.dart';
import '../services/usb_scanner_service.dart';

/// State module for the RF scanner (11th AppState module).
/// Manages scanner connection, detection processing, and map data.
///
/// BLE is the primary transport on both iOS and Android. On Android, when a USB
/// cable is detected the active transport auto-upgrades to USB serial so the
/// ESP32 can reclaim BLE bandwidth for scanning.
class ScannerState extends ChangeNotifier {
  ScannerService _activeScanner;
  final RfDetectionDatabase _db;

  /// BLE scanner — always exists, used as primary transport.
  final ScannerService _bleScanner;

  /// USB scanner — Android only, used when a cable is attached.
  final ScannerService? _usbScanner;

  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<ScannerConnectionStatus>? _statusSubscription;

  /// Subscription on the USB scanner's status stream so we can detect
  /// USB attach/detach and auto-switch transports.
  StreamSubscription<ScannerConnectionStatus>? _usbStatusSubscription;

  ScannerConnectionStatus _connectionStatus =
      ScannerConnectionStatus.disconnected;
  final List<RfDetection> _recentDetections = [];
  int _detectionCount = 0;
  LatLng? _currentGpsPosition;
  double? _currentGpsAccuracy;

  static const int _maxRecentDetections = 50;

  /// Production constructor — BLE primary, USB on Android.
  ///
  /// When [scanner] is provided (e.g. in tests), it becomes the sole scanner
  /// and no USB transport is created. In production, a [BleScannerService] is
  /// the primary scanner and [UsbScannerService] is created on Android.
  ScannerState({ScannerService? scanner, RfDetectionDatabase? db})
      : _bleScanner = scanner ?? BleScannerService(),
        _usbScanner = scanner != null
            ? null
            : (_isAndroid ? UsbScannerService() : null),
        // Temporary — overwritten in constructor body to point at _bleScanner
        _activeScanner = scanner ?? _placeholder,
        _db = db ?? RfDetectionDatabase() {
    _activeScanner = _bleScanner;
  }

  /// Sentinel that is never used — exists only because Dart initializer lists
  /// cannot reference other initializer-list members. The constructor body
  /// immediately replaces `_activeScanner` with `_bleScanner`.
  static final ScannerService _placeholder = _NoOpScanner();

  /// Cached platform check. Safe to evaluate at class-load time because
  /// `dart:io` Platform is available on mobile/desktop (never on web, but
  /// this app does not target web).
  static final bool _isAndroid = Platform.isAndroid;

  // Public getters
  ScannerConnectionStatus get connectionStatus => _connectionStatus;
  List<RfDetection> get recentDetections =>
      List.unmodifiable(_recentDetections);
  int get detectionCount => _detectionCount;
  bool get isConnected => _activeScanner.isConnected;
  String? get lastError => _activeScanner.lastError;

  /// Which transport is currently active (BLE or USB).
  ScannerTransportType get activeTransportType =>
      _activeScanner == _usbScanner
          ? ScannerTransportType.usb
          : ScannerTransportType.ble;

  /// Initialize scanner: open database, start BLE transport, and optionally
  /// start USB monitoring on Android.
  Future<void> init() async {
    await _db.init();

    // Load initial detection count
    final stats = await _db.getStats();
    _detectionCount = stats['total'] as int;

    // Subscribe to the active scanner
    _subscribeToScanner(_activeScanner);

    // Start BLE scanner
    await _bleScanner.init();

    // On Android, also start USB scanner to listen for hotplug events.
    // When USB connects, we auto-switch transport.
    if (_usbScanner case final usb?) {
      await usb.init();
      _usbStatusSubscription = usb.statusStream.listen(_onUsbStatusChange);
    }

    notifyListeners();
  }

  void _subscribeToScanner(ScannerService scanner) {
    _statusSubscription?.cancel();
    _eventSubscription?.cancel();

    _statusSubscription = scanner.statusStream.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    _eventSubscription = scanner.events.listen(_onDetectionEvent);
  }

  /// Handle USB status changes to auto-switch transport on Android.
  void _onUsbStatusChange(ScannerConnectionStatus usbStatus) {
    if (usbStatus == ScannerConnectionStatus.connected &&
        _activeScanner != _usbScanner) {
      // USB cable just attached — switch to USB for higher throughput
      debugPrint('[ScannerState] USB connected — switching to USB transport');
      _switchTransport(_usbScanner!);
      // Disconnect BLE client so ESP32 can boost scan duty
      _bleScanner.disconnect();
    } else if (usbStatus == ScannerConnectionStatus.disconnected &&
        _activeScanner == _usbScanner) {
      // USB cable detached — switch back to BLE
      debugPrint('[ScannerState] USB disconnected — switching to BLE transport');
      _switchTransport(_bleScanner);
      // Reconnect BLE
      _bleScanner.connect();
    }
  }

  void _switchTransport(ScannerService newScanner) {
    _activeScanner = newScanner;
    _subscribeToScanner(newScanner);
    _connectionStatus = newScanner.status;
    notifyListeners();
  }

  /// Manually trigger a reconnect attempt.
  Future<bool> reconnect() async {
    return await _activeScanner.connect();
  }

  /// Disconnect from the active scanner.
  Future<void> disconnect() async {
    await _activeScanner.disconnect();
  }

  /// Process an incoming detection event from the FlockSquawk.
  Future<void> _onDetectionEvent(Map<String, dynamic> json) async {
    try {
      // Get current GPS position
      await _updateGpsPosition();

      if (_currentGpsPosition == null) {
        debugPrint('[ScannerState] Skipping detection — no GPS fix');
        return;
      }

      final now = DateTime.now();

      // Create detection and sighting from JSON
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
    _usbStatusSubscription?.cancel();
    // dispose() is async but ChangeNotifier.dispose() is not — fire and forget
    _bleScanner.dispose();
    _usbScanner?.dispose();
    _db.close();
    super.dispose();
  }
}

/// Minimal no-op scanner used only as an initializer-list placeholder.
/// Immediately replaced by the constructor body — never receives events.
class _NoOpScanner implements ScannerService {
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Stream<ScannerConnectionStatus> get statusStream => const Stream.empty();
  @override
  ScannerConnectionStatus get status => ScannerConnectionStatus.disconnected;
  @override
  bool get isConnected => false;
  @override
  String? get lastError => null;
  @override
  Future<void> init() async {}
  @override
  Future<bool> connect() async => false;
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
}

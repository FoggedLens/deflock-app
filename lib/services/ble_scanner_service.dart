import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'scanner_service.dart';
import 'json_line_parser.dart';

/// FlockSquawk BLE GATT UUIDs — must match the ESP32 firmware.
class FlockSquawkBleUuids {
  static final Guid service = Guid('a1b2c3d4-e5f6-7890-abcd-ef0123456789');
  static final Guid txCharacteristic =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef01234567aa');
}

/// BLE transport for FlockSquawk.
///
/// Scans for a device advertising the FlockSquawk service UUID, connects,
/// subscribes to notify on the TX characteristic, and feeds incoming bytes
/// through [JsonLineParser] to produce detection events.
class BleScannerService with JsonLineParser implements ScannerService {
  BluetoothDevice? _device;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  Timer? _reconnectTimer;

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController =
      StreamController<ScannerConnectionStatus>.broadcast();

  ScannerConnectionStatus _status = ScannerConnectionStatus.disconnected;
  String? _lastError;
  bool _disposed = false;

  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const Duration _scanTimeout = Duration(seconds: 10);
  static const int _maxReconnectAttempts = 5;
  int _reconnectAttempts = 0;

  @override
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  @override
  Stream<ScannerConnectionStatus> get statusStream => _statusController.stream;

  @override
  ScannerConnectionStatus get status => _status;

  @override
  bool get isConnected => _status == ScannerConnectionStatus.connected;

  @override
  String? get lastError => _lastError;

  // -- JsonLineParser callback --
  @override
  void onJsonEvent(Map<String, dynamic> json) {
    _eventController.add(json);
  }

  @override
  Future<void> init() async {
    // Monitor adapter state for permissions / BLE off
    _adapterSubscription =
        FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off ||
          state == BluetoothAdapterState.unauthorized) {
        _setError(state == BluetoothAdapterState.off
            ? 'Bluetooth is turned off'
            : 'Bluetooth permission denied');
      }
    });

    await connect();
  }

  @override
  Future<bool> connect() async {
    if (_disposed) return false;
    if (_status == ScannerConnectionStatus.connected) return true;

    // Reset retry counter when connect() is called externally (e.g. manual
    // reconnect), so the user isn't stuck after exhausting auto-retries.
    if (_status == ScannerConnectionStatus.error) {
      _reconnectAttempts = 0;
    }

    _setStatus(ScannerConnectionStatus.connecting);

    try {
      // Check adapter state
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        _setError('Bluetooth is not available');
        return false;
      }

      // Scan for FlockSquawk devices
      _device = await _scanForDevice();
      if (_device == null) {
        debugPrint('[BleScanner] No FlockSquawk device found');
        _setStatus(ScannerConnectionStatus.disconnected);
        _scheduleReconnect();
        return false;
      }

      debugPrint('[BleScanner] Found device: ${_device!.remoteId}');

      // Connect
      await _device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 10),
      );

      // Listen for disconnections *after* the link is established.
      // Subscribing before connect() causes flutter_blue_plus to emit the
      // current state (disconnected) immediately, which races with connect().
      _connectionSubscription?.cancel();
      _connectionSubscription = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            _status == ScannerConnectionStatus.connected) {
          debugPrint('[BleScanner] Device disconnected');
          _handleDisconnect();
        }
      });

      // Request larger MTU (iOS negotiates automatically; explicit on Android)
      await _device!.requestMtu(512);

      // Discover services and subscribe to notifications
      final services = await _device!.discoverServices();
      final flockService = services.firstWhere(
        (s) => s.serviceUuid == FlockSquawkBleUuids.service,
        orElse: () => throw StateError('FlockSquawk service not found'),
      );

      final txChar = flockService.characteristics.firstWhere(
        (c) => c.characteristicUuid == FlockSquawkBleUuids.txCharacteristic,
        orElse: () => throw StateError('TX characteristic not found'),
      );

      // Enable notifications
      await txChar.setNotifyValue(true);

      resetLineBuffer();

      _characteristicSubscription?.cancel();
      _characteristicSubscription = txChar.onValueReceived.listen(
        (value) => processBytes(Uint8List.fromList(value)),
      );

      _setStatus(ScannerConnectionStatus.connected);
      _reconnectAttempts = 0;
      debugPrint('[BleScanner] Connected and subscribed');
      return true;
    } catch (e) {
      // Clean up partially-established connection
      _characteristicSubscription?.cancel();
      _characteristicSubscription = null;
      _connectionSubscription?.cancel();
      _connectionSubscription = null;
      if (_device != null) {
        try {
          await _device!.disconnect();
        } catch (_) {}
        _device = null;
      }

      _setError('BLE connection failed: $e');
      _scheduleReconnect();
      return false;
    }
  }

  /// Scan for a device advertising the FlockSquawk service UUID.
  Future<BluetoothDevice?> _scanForDevice() async {
    final completer = Completer<BluetoothDevice?>();

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        for (final result in results) {
          final hasFlockService = result.advertisementData.serviceUuids
              .contains(FlockSquawkBleUuids.service);
          if (hasFlockService && !completer.isCompleted) {
            FlutterBluePlus.stopScan();
            completer.complete(result.device);
            return;
          }
        }
      },
      onError: (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      },
    );

    await FlutterBluePlus.startScan(
      withServices: [FlockSquawkBleUuids.service],
      timeout: _scanTimeout,
    );

    // If scan completes without finding a device
    if (!completer.isCompleted) {
      completer.complete(null);
    }

    _scanSubscription?.cancel();
    _scanSubscription = null;

    return completer.future;
  }

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _characteristicSubscription?.cancel();
    _characteristicSubscription = null;

    _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _scanSubscription?.cancel();
    _scanSubscription = null;

    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (e) {
        debugPrint('[BleScanner] Error disconnecting: $e');
      }
      _device = null;
    }

    resetLineBuffer();
    _setStatus(ScannerConnectionStatus.disconnected);
    debugPrint('[BleScanner] Disconnected');
  }

  void _handleDisconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _characteristicSubscription?.cancel();
    _characteristicSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _device = null;

    resetLineBuffer();
    _setStatus(ScannerConnectionStatus.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[BleScanner] Max reconnect attempts reached, giving up');
      _setError('Unable to connect after $_maxReconnectAttempts attempts');
      return;
    }
    _reconnectTimer?.cancel();
    // Exponential backoff: 2s, 4s, 8s, 16s, 32s
    final delay = _reconnectDelay * (1 << _reconnectAttempts);
    _reconnectAttempts++;
    _reconnectTimer = Timer(delay, () {
      if (!_disposed && _status != ScannerConnectionStatus.connected) {
        debugPrint('[BleScanner] Auto-reconnecting (attempt $_reconnectAttempts/$_maxReconnectAttempts)...');
        connect();
      }
    });
  }

  void _setStatus(ScannerConnectionStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    _lastError = null;
    _statusController.add(newStatus);
  }

  void _setError(String message) {
    debugPrint('[BleScanner] Error: $message');
    _lastError = message;
    _status = ScannerConnectionStatus.error;
    _statusController.add(ScannerConnectionStatus.error);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _adapterSubscription?.cancel();
    await disconnect();
    _eventController.close();
    _statusController.close();
  }
}

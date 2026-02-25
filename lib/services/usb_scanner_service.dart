import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';

import 'scanner_service.dart';
import 'json_line_parser.dart';

// Re-export so existing `import 'usb_scanner_service.dart' show ScannerConnectionStatus`
// continues to work.
export 'scanner_service.dart' show ScannerConnectionStatus;

/// Manages USB serial connection to the FlockSquawk M5StickC device.
/// Parses newline-delimited JSON events and exposes them as a stream.
class UsbScannerService with JsonLineParser implements ScannerService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _portSubscription;
  StreamSubscription<UsbEvent>? _hotplugSubscription;
  Timer? _heartbeatTimer;

  /// Single newline byte sent as heartbeat — allocated once.
  static final _heartbeatByte = Uint8List.fromList([0x0A]);

  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController =
      StreamController<ScannerConnectionStatus>.broadcast();

  ScannerConnectionStatus _status = ScannerConnectionStatus.disconnected;
  String? _lastError;

  static const int _baudRate = 115200;

  /// Stream of parsed JSON detection events.
  @override
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  /// Stream of connection status changes.
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

  /// Start listening for USB device hotplug and attempt initial connection.
  @override
  Future<void> init() async {
    // Listen for USB attach/detach
    _hotplugSubscription = UsbSerial.usbEventStream?.listen((event) {
      debugPrint('[UsbScanner] USB event: ${event.event}');
      if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
        connect();
      } else if (event.event == UsbEvent.ACTION_USB_DETACHED) {
        _handleDisconnect();
      }
    });

    // Try to connect to an already-attached device
    await connect();
  }

  /// Attempt to find and connect to a USB serial device.
  @override
  Future<bool> connect() async {
    if (_status == ScannerConnectionStatus.connected) return true;

    _setStatus(ScannerConnectionStatus.connecting);

    try {
      final devices = await UsbSerial.listDevices();
      debugPrint('[UsbScanner] Found ${devices.length} USB device(s)');

      if (devices.isEmpty) {
        _setStatus(ScannerConnectionStatus.disconnected);
        return false;
      }

      // Use the first available serial device
      final device = devices.first;
      debugPrint(
          '[UsbScanner] Connecting to ${device.productName} (VID:${device.vid} PID:${device.pid})');

      _port = await device.create();
      if (_port == null) {
        _setError('Failed to create serial port');
        return false;
      }

      final opened = await _port!.open();
      if (!opened) {
        _setError('Failed to open serial port');
        _port = null;
        return false;
      }

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        _baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      resetLineBuffer();

      // Listen to incoming serial data
      _portSubscription = _port!.inputStream?.listen(
        (data) => processBytes(data),
        onError: (error) {
          debugPrint('[UsbScanner] Serial stream error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[UsbScanner] Serial stream closed');
          _handleDisconnect();
        },
      );

      // Start heartbeat so ESP32 can detect active serial vs wall charger
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        try {
          _port?.write(_heartbeatByte);
        } catch (e) {
          debugPrint('[UsbScanner] Heartbeat write failed: $e');
        }
      });

      _setStatus(ScannerConnectionStatus.connected);
      debugPrint('[UsbScanner] Connected successfully');
      return true;
    } catch (e) {
      _setError('Connection failed: $e');
      return false;
    }
  }

  /// Disconnect from the USB device.
  @override
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    await _portSubscription?.cancel();
    _portSubscription = null;

    if (_port != null) {
      try {
        await _port!.close();
      } catch (e) {
        debugPrint('[UsbScanner] Error closing port: $e');
      }
      _port = null;
    }

    resetLineBuffer();
    _setStatus(ScannerConnectionStatus.disconnected);
    debugPrint('[UsbScanner] Disconnected');
  }

  /// Handle unexpected disconnection (USB detach, stream error).
  /// Closes port if still open, then updates status.
  void _handleDisconnect() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _portSubscription?.cancel();
    _portSubscription = null;

    // Close port if it's still around — fire and forget since we're
    // already in a disconnect path and can't meaningfully handle errors.
    final port = _port;
    _port = null;
    if (port != null) {
      port.close().catchError((Object e) {
        debugPrint('[UsbScanner] Error closing port during disconnect: $e');
        return false;
      });
    }

    resetLineBuffer();
    _setStatus(ScannerConnectionStatus.disconnected);
  }

  void _setStatus(ScannerConnectionStatus newStatus) {
    if (_status == newStatus) return;
    _status = newStatus;
    _lastError = null;
    _statusController.add(newStatus);
  }

  void _setError(String message) {
    debugPrint('[UsbScanner] Error: $message');
    _lastError = message;
    _status = ScannerConnectionStatus.error;
    _statusController.add(ScannerConnectionStatus.error);
  }

  @override
  Future<void> dispose() async {
    _hotplugSubscription?.cancel();
    await disconnect();
    _eventController.close();
    _statusController.close();
  }

  /// Feed raw bytes into the serial parser for testing.
  @visibleForTesting
  void processSerialDataForTesting(Uint8List data) => processBytes(data);

  /// Whether the heartbeat timer is currently active (for testing).
  @visibleForTesting
  bool get isHeartbeatActive => _heartbeatTimer?.isActive ?? false;
}

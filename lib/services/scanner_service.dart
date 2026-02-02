import 'dart:async';

/// Which transport layer is currently active.
enum ScannerTransportType { ble, usb }

/// Connection status for a scanner transport (USB, BLE, etc.).
enum ScannerConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Abstract interface for scanner transports.
///
/// Both [UsbScannerService] and [BleScannerService] implement this so that
/// [ScannerState] can swap transports without caring about the underlying
/// mechanism.
abstract class ScannerService {
  /// Stream of parsed JSON detection events (`target_detected`).
  Stream<Map<String, dynamic>> get events;

  /// Stream of connection status changes.
  Stream<ScannerConnectionStatus> get statusStream;

  /// Current connection status snapshot.
  ScannerConnectionStatus get status;

  /// Whether the transport is currently connected.
  bool get isConnected;

  /// Human-readable description of the last error, or null.
  String? get lastError;

  /// Start listening for devices and attempt initial connection.
  Future<void> init();

  /// Attempt to connect to a device.
  Future<bool> connect();

  /// Disconnect from the device.
  Future<void> disconnect();

  /// Release all resources.
  Future<void> dispose();
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:deflockapp/services/ble_scanner_service.dart';
import 'package:deflockapp/services/scanner_service.dart';
import 'package:deflockapp/services/json_line_parser.dart';
import '../fixtures/serial_json_fixtures.dart';

Uint8List _encode(String s) => Uint8List.fromList(utf8.encode(s));

/// Test harness that bypasses actual BLE hardware.
///
/// Uses the same JsonLineParser mixin as BleScannerService so we can test
/// the parsing + eventing pipeline identically. The actual BLE connection
/// logic requires a real adapter and can only be integration-tested on device.
class TestableBleScannerServiceCore with JsonLineParser {
  final List<Map<String, dynamic>> events = [];

  @override
  void onJsonEvent(Map<String, dynamic> json) {
    events.add(json);
  }
}

void main() {
  // ---------------------------------------------------------------------------
  // BLE UUIDs
  // ---------------------------------------------------------------------------
  group('FlockSquawk BLE UUIDs', () {
    test('service UUID is correct', () {
      expect(
        FlockSquawkBleUuids.service.toString(),
        'a1b2c3d4-e5f6-7890-abcd-ef0123456789',
      );
    });

    test('TX characteristic UUID is correct', () {
      expect(
        FlockSquawkBleUuids.txCharacteristic.toString(),
        'a1b2c3d4-e5f6-7890-abcd-ef01234567aa',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // JsonLineParser via BLE notifications
  // ---------------------------------------------------------------------------
  // These tests verify that the same parsing mixin works correctly when fed
  // data in BLE-notification-sized chunks (simulating MTU fragmentation).
  group('BLE notification parsing', () {
    late TestableBleScannerServiceCore core;

    setUp(() {
      core = TestableBleScannerServiceCore();
    });

    test('single notification containing full line emits event', () {
      final json = jsonEncode(makeDetectionJson());
      core.processBytes(_encode('$json\n'));

      expect(core.events, hasLength(1));
      expect(core.events.first['event'], 'target_detected');
    });

    test('JSON split across two MTU-sized notifications reassembles', () {
      final json = jsonEncode(makeDetectionJson());
      // Simulate 20-byte MTU chunks (minimum BLE MTU - 3 bytes overhead)
      const chunkSize = 20;
      final fullLine = '$json\n';

      for (var i = 0; i < fullLine.length; i += chunkSize) {
        final end =
            (i + chunkSize > fullLine.length) ? fullLine.length : i + chunkSize;
        core.processBytes(_encode(fullLine.substring(i, end)));
      }

      expect(core.events, hasLength(1));
    });

    test('multiple events across many small notifications', () {
      final json1 = jsonEncode(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:01'));
      final json2 = jsonEncode(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:02'));
      final fullData = '$json1\n$json2\n';

      // Feed byte-by-byte (worst case fragmentation)
      for (var i = 0; i < fullData.length; i++) {
        core.processBytes(_encode(fullData[i]));
      }

      expect(core.events, hasLength(2));
    });

    test('notification with \\r\\n line ending', () {
      final json = jsonEncode(makeDetectionJson());
      core.processBytes(_encode('$json\r\n'));

      expect(core.events, hasLength(1));
    });

    test('non-JSON notification data is ignored', () {
      core.processBytes(_encode('ESP32 BLE debug output\n'));

      expect(core.events, isEmpty);
    });

    test('buffer overflow protection works with BLE data', () {
      // Feed >4096 bytes without newline
      core.processBytes(_encode('x' * 4097));
      expect(core.lineBufferForTesting, isEmpty);

      // Should still work after overflow
      final json = jsonEncode(makeDetectionJson());
      core.processBytes(_encode('$json\n'));
      expect(core.events, hasLength(1));
    });

    test('partial notification followed by rest works', () {
      final json = jsonEncode(makeDetectionJson());
      final mid = json.length ~/ 2;

      // First notification: partial JSON
      core.processBytes(_encode(json.substring(0, mid)));
      expect(core.events, isEmpty);

      // Second notification: rest of JSON + newline
      core.processBytes(_encode('${json.substring(mid)}\n'));
      expect(core.events, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------
  group('BleScannerService initial state', () {
    test('implements ScannerService', () async {
      final svc = BleScannerService();
      // Compile-time check: BleScannerService implements ScannerService
      // ignore: unnecessary_type_check
      expect(svc is ScannerService, isTrue);
      await svc.dispose();
    });
  });
}

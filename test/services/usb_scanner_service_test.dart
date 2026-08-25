import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:deflockapp/services/usb_scanner_service.dart';
import '../fixtures/serial_json_fixtures.dart';

Uint8List _encode(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late UsbScannerService service;

  setUp(() {
    service = UsbScannerService();
  });

  tearDown(() async {
    await service.dispose();
  });

  // ---------------------------------------------------------------------------
  // Line buffering
  // ---------------------------------------------------------------------------
  group('Line buffering', () {
    test('complete line emits event', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      service.processSerialDataForTesting(_encode('$json\n'));

      // Allow stream event to propagate
      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first['event'], 'target_detected');
    });

    test('partial line is buffered', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      final half = json.substring(0, json.length ~/ 2);
      service.processSerialDataForTesting(_encode(half));

      await Future.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(service.lineBufferForTesting, half);
    });

    test('line split across two chunks reassembles', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      final mid = json.length ~/ 2;
      service.processSerialDataForTesting(_encode(json.substring(0, mid)));
      service.processSerialDataForTesting(_encode('${json.substring(mid)}\n'));

      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
    });

    test('line split across three chunks reassembles', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      final third = json.length ~/ 3;
      service.processSerialDataForTesting(_encode(json.substring(0, third)));
      service.processSerialDataForTesting(
          _encode(json.substring(third, third * 2)));
      service.processSerialDataForTesting(
          _encode('${json.substring(third * 2)}\n'));

      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
    });

    test('multiple lines in one chunk each emit', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json1 = jsonEncode(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:01'));
      final json2 = jsonEncode(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:02'));
      service.processSerialDataForTesting(_encode('$json1\n$json2\n'));

      await Future.delayed(Duration.zero);
      expect(events, hasLength(2));
    });

    test('empty lines are skipped', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      service.processSerialDataForTesting(_encode('\n\n$json\n\n'));

      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
    });

    test('\\r\\n trimmed correctly', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      service.processSerialDataForTesting(_encode('$json\r\n'));

      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
    });

    test('trailing data kept in buffer after processing complete lines', () {
      final json = jsonEncode(makeDetectionJson());
      service.processSerialDataForTesting(_encode('$json\npartial'));

      expect(service.lineBufferForTesting, 'partial');
    });
  });

  // ---------------------------------------------------------------------------
  // Buffer overflow
  // ---------------------------------------------------------------------------
  group('Buffer overflow', () {
    test('clears buffer when exceeding 4096 chars', () {
      // Feed more than 4096 chars without a newline
      final bigChunk = 'x' * 4097;
      service.processSerialDataForTesting(_encode(bigChunk));
      expect(service.lineBufferForTesting, isEmpty);
    });

    test('resumes normal operation after overflow clear', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      // Overflow
      service.processSerialDataForTesting(_encode('x' * 4097));
      expect(service.lineBufferForTesting, isEmpty);

      // Normal line should work
      final json = jsonEncode(makeDetectionJson());
      service.processSerialDataForTesting(_encode('$json\n'));
      await Future.delayed(Duration.zero);
      expect(events, hasLength(1));
    });

    test('does not clear at exactly 4096 chars', () {
      final chunk = 'x' * 4096;
      service.processSerialDataForTesting(_encode(chunk));
      expect(service.lineBufferForTesting, chunk);
    });
  });

  // ---------------------------------------------------------------------------
  // JSON parsing
  // ---------------------------------------------------------------------------
  group('JSON parsing', () {
    test('target_detected event is emitted', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      service.processSerialDataForTesting(_encode('$json\n'));
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first['event'], 'target_detected');
    });

    test('other event types are ignored', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json =
          jsonEncode(makeDetectionJson(event: 'status_update'));
      service.processSerialDataForTesting(_encode('$json\n'));
      await Future.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('JSON without event field is ignored', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      service.processSerialDataForTesting(
          _encode('${jsonEncode({"foo": "bar"})}\n'));
      await Future.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('non-JSON lines are ignored', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      service.processSerialDataForTesting(
          _encode('ESP32 booting up...\n'));
      await Future.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('malformed JSON is ignored', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      service.processSerialDataForTesting(
          _encode('{"event": "target_detected", broken\n'));
      await Future.delayed(Duration.zero);

      expect(events, isEmpty);
    });

    test('empty JSON object is ignored', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      service.processSerialDataForTesting(_encode('{}\n'));
      await Future.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Event stream
  // ---------------------------------------------------------------------------
  group('Event stream', () {
    test('is a broadcast stream', () {
      // Should not throw — broadcast streams allow multiple listeners
      service.events.listen((_) {});
      service.events.listen((_) {});
    });

    test('events received after subscribe', () async {
      final events = <Map<String, dynamic>>[];
      service.events.listen(events.add);

      final json = jsonEncode(makeDetectionJson());
      service.processSerialDataForTesting(_encode('$json\n'));
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------
  group('Initial state', () {
    test('status is disconnected', () {
      expect(service.status, ScannerConnectionStatus.disconnected);
    });

    test('isConnected is false', () {
      expect(service.isConnected, isFalse);
    });

    test('lastError is null', () {
      expect(service.lastError, isNull);
    });

    test('heartbeat is not active', () {
      expect(service.isHeartbeatActive, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Heartbeat lifecycle
  // ---------------------------------------------------------------------------
  group('Heartbeat lifecycle', () {
    test('heartbeat is not active before connect', () {
      expect(service.isHeartbeatActive, isFalse);
    });

    test('heartbeat is stopped after dispose', () async {
      final localService = UsbScannerService();
      await localService.dispose();
      expect(localService.isHeartbeatActive, isFalse);
    });

    test('heartbeat is stopped after disconnect', () async {
      // disconnect() on a never-connected service should be safe
      await service.disconnect();
      expect(service.isHeartbeatActive, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------
  group('Dispose', () {
    test('stream controllers are closed after dispose', () async {
      // Use a separate instance so the shared `service` isn't double-disposed
      // by tearDown.
      final localService = UsbScannerService();
      await localService.dispose();

      // Listening after close should emit done immediately
      var eventsDone = false;
      var statusDone = false;
      localService.events.listen((_) {}, onDone: () => eventsDone = true);
      localService.statusStream
          .listen((_) {}, onDone: () => statusDone = true);
      await Future.delayed(Duration.zero);

      expect(eventsDone, isTrue);
      expect(statusDone, isTrue);
    });
  });
}

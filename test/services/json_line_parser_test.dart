import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:deflockapp/services/json_line_parser.dart';
import '../fixtures/serial_json_fixtures.dart';

Uint8List _encode(String s) => Uint8List.fromList(utf8.encode(s));

/// Concrete test class using the mixin.
class TestParser with JsonLineParser {
  final List<Map<String, dynamic>> events = [];

  @override
  void onJsonEvent(Map<String, dynamic> json) {
    events.add(json);
  }

  /// Expose protected method for testing.
  void reset() => resetLineBuffer();
}

void main() {
  late TestParser parser;

  setUp(() {
    parser = TestParser();
  });

  // ---------------------------------------------------------------------------
  // Line buffering
  // ---------------------------------------------------------------------------
  group('Line buffering', () {
    test('complete line emits event', () {
      final json = jsonEncode(makeDetectionJson());
      parser.processBytes(_encode('$json\n'));

      expect(parser.events, hasLength(1));
      expect(parser.events.first['event'], 'target_detected');
    });

    test('partial line is buffered', () {
      final json = jsonEncode(makeDetectionJson());
      final half = json.substring(0, json.length ~/ 2);
      parser.processBytes(_encode(half));

      expect(parser.events, isEmpty);
      expect(parser.lineBufferForTesting, half);
    });

    test('line split across two chunks reassembles', () {
      final json = jsonEncode(makeDetectionJson());
      final mid = json.length ~/ 2;
      parser.processBytes(_encode(json.substring(0, mid)));
      parser.processBytes(_encode('${json.substring(mid)}\n'));

      expect(parser.events, hasLength(1));
    });

    test('line split across three chunks reassembles', () {
      final json = jsonEncode(makeDetectionJson());
      final third = json.length ~/ 3;
      parser.processBytes(_encode(json.substring(0, third)));
      parser.processBytes(_encode(json.substring(third, third * 2)));
      parser.processBytes(_encode('${json.substring(third * 2)}\n'));

      expect(parser.events, hasLength(1));
    });

    test('multiple lines in one chunk each emit', () {
      final json1 = jsonEncode(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:01'));
      final json2 = jsonEncode(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:02'));
      parser.processBytes(_encode('$json1\n$json2\n'));

      expect(parser.events, hasLength(2));
    });

    test('empty lines are skipped', () {
      final json = jsonEncode(makeDetectionJson());
      parser.processBytes(_encode('\n\n$json\n\n'));

      expect(parser.events, hasLength(1));
    });

    test('\\r\\n trimmed correctly', () {
      final json = jsonEncode(makeDetectionJson());
      parser.processBytes(_encode('$json\r\n'));

      expect(parser.events, hasLength(1));
    });

    test('trailing data kept in buffer after processing complete lines', () {
      final json = jsonEncode(makeDetectionJson());
      parser.processBytes(_encode('$json\npartial'));

      expect(parser.lineBufferForTesting, 'partial');
    });
  });

  // ---------------------------------------------------------------------------
  // Buffer overflow
  // ---------------------------------------------------------------------------
  group('Buffer overflow', () {
    test('clears buffer when exceeding 4096 chars', () {
      final bigChunk = 'x' * 4097;
      parser.processBytes(_encode(bigChunk));
      expect(parser.lineBufferForTesting, isEmpty);
    });

    test('resumes normal operation after overflow clear', () {
      // Overflow
      parser.processBytes(_encode('x' * 4097));
      expect(parser.lineBufferForTesting, isEmpty);

      // Normal line should work
      final json = jsonEncode(makeDetectionJson());
      parser.processBytes(_encode('$json\n'));
      expect(parser.events, hasLength(1));
    });

    test('does not clear at exactly 4096 chars', () {
      final chunk = 'x' * 4096;
      parser.processBytes(_encode(chunk));
      expect(parser.lineBufferForTesting, chunk);
    });
  });

  // ---------------------------------------------------------------------------
  // JSON parsing
  // ---------------------------------------------------------------------------
  group('JSON parsing', () {
    test('target_detected event is emitted', () {
      final json = jsonEncode(makeDetectionJson());
      parser.processBytes(_encode('$json\n'));

      expect(parser.events, hasLength(1));
      expect(parser.events.first['event'], 'target_detected');
    });

    test('other event types are ignored', () {
      final json = jsonEncode(makeDetectionJson(event: 'status_update'));
      parser.processBytes(_encode('$json\n'));

      expect(parser.events, isEmpty);
    });

    test('JSON without event field is ignored', () {
      parser.processBytes(_encode('${jsonEncode({"foo": "bar"})}\n'));

      expect(parser.events, isEmpty);
    });

    test('non-JSON lines are ignored', () {
      parser.processBytes(_encode('ESP32 booting up...\n'));

      expect(parser.events, isEmpty);
    });

    test('malformed JSON is ignored', () {
      parser.processBytes(
          _encode('{"event": "target_detected", broken\n'));

      expect(parser.events, isEmpty);
    });

    test('empty JSON object is ignored', () {
      parser.processBytes(_encode('{}\n'));

      expect(parser.events, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // resetLineBuffer
  // ---------------------------------------------------------------------------
  group('resetLineBuffer', () {
    test('clears partial data', () {
      parser.processBytes(_encode('partial'));
      expect(parser.lineBufferForTesting, 'partial');

      parser.reset();
      expect(parser.lineBufferForTesting, isEmpty);
    });
  });
}

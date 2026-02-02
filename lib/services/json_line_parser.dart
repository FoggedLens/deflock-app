import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Mixin that handles newline-delimited JSON parsing from raw byte streams.
///
/// Both USB serial and BLE characteristic notifications deliver bytes that may
/// be split across multiple chunks. This mixin reassembles complete lines,
/// parses JSON, and emits `target_detected` events via [onJsonEvent].
mixin JsonLineParser {
  String _lineBuffer = '';

  /// Override to handle a fully parsed `target_detected` JSON event.
  void onJsonEvent(Map<String, dynamic> json);

  /// Feed raw bytes into the line-buffering parser.
  ///
  /// Complete newline-delimited lines are extracted, parsed as JSON, and
  /// dispatched via [onJsonEvent] if the `event` field is `target_detected`.
  void processBytes(Uint8List data) {
    final chunk = utf8.decode(data, allowMalformed: true);
    _lineBuffer += chunk;

    // Process all complete lines
    while (_lineBuffer.contains('\n')) {
      final newlineIndex = _lineBuffer.indexOf('\n');
      final line = _lineBuffer.substring(0, newlineIndex).trim();
      _lineBuffer = _lineBuffer.substring(newlineIndex + 1);

      if (line.isEmpty) continue;

      _parseLine(line);
    }

    // Prevent unbounded buffer growth from non-JSON output
    if (_lineBuffer.length > 4096) {
      debugPrint('[JsonLineParser] Line buffer overflow, clearing');
      _lineBuffer = '';
    }
  }

  void _parseLine(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final event = json['event'] as String?;

      if (event == 'target_detected') {
        onJsonEvent(json);
      }
    } catch (e) {
      // Non-JSON output (boot messages, debug prints) — ignore
    }
  }

  /// Reset the internal line buffer.
  @protected
  void resetLineBuffer() {
    _lineBuffer = '';
  }

  /// Expose line buffer for test assertions.
  @visibleForTesting
  String get lineBufferForTesting => _lineBuffer;
}

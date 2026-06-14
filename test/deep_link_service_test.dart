import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Node deep link URL parsing', () {
    test('extracts node ID from valid link', () {
      final uri = Uri.parse('deflockapp://node?id=1234567890');
      expect(uri.host, 'node');
      expect(uri.queryParameters['id'], '1234567890');
    });

    test('returns null for missing id param', () {
      final uri = Uri.parse('deflockapp://node');
      expect(uri.queryParameters['id'], isNull);
    });

    test('returns null for empty id param', () {
      final uri = Uri.parse('deflockapp://node?id=');
      expect(uri.queryParameters['id'], '');
    });

    test('returns null for non-numeric id', () {
      final uri = Uri.parse('deflockapp://node?id=abc');
      expect(int.tryParse(uri.queryParameters['id'] ?? ''), isNull);
    });
  });
}

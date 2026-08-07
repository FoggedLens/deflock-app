import 'package:flutter_test/flutter_test.dart';

/// Mirrors ProximityAlertService._notificationId. Kept in sync deliberately:
/// the real one is private, and this pins the contract the plugin enforces —
/// notification ids must fit in a signed 32-bit int.
int notificationId(int nodeId) => nodeId.abs() % 0x7FFFFFFF;

const int maxInt32 = 2147483647;

void main() {
  group('notificationId', () {
    test('folds real-world OSM node ids into 32-bit range', () {
      // The id from the crash, plus ids around the current OSM high-water mark.
      const ids = [
        12741890927,
        1,
        2147483647,
        2147483648,
        9999999999,
        13000000000,
      ];

      for (final id in ids) {
        final result = notificationId(id);
        expect(result, greaterThanOrEqualTo(0), reason: 'id $id went negative');
        expect(result, lessThanOrEqualTo(maxInt32), reason: 'id $id overflowed');
      }
    });

    test('handles negative ids, which OSM uses for not-yet-uploaded nodes', () {
      for (final id in [-1, -12741890927, -2147483648]) {
        final result = notificationId(id);
        expect(result, greaterThanOrEqualTo(0));
        expect(result, lessThanOrEqualTo(maxInt32));
      }
    });

    test('is deterministic, so a repeat alert replaces rather than stacks', () {
      expect(notificationId(12741890927), notificationId(12741890927));
    });

    test('separates adjacent node ids', () {
      final a = notificationId(12741890927);
      final b = notificationId(12741890928);
      expect(a, isNot(b));
    });
  });
}

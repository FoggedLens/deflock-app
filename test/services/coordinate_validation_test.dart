import 'package:flutter_test/flutter_test.dart';

import 'package:deflockapp/services/coordinate_validation.dart';

void main() {
  group('isValidLatitude', () {
    test('accepts in-range values', () {
      expect(isValidLatitude(0), isTrue);
      expect(isValidLatitude(37.7749), isTrue);
      expect(isValidLatitude(90), isTrue);
      expect(isValidLatitude(-90), isTrue);
    });

    test('rejects NaN and Infinite', () {
      expect(isValidLatitude(double.nan), isFalse);
      expect(isValidLatitude(double.infinity), isFalse);
      expect(isValidLatitude(double.negativeInfinity), isFalse);
    });

    test('rejects out-of-range values', () {
      expect(isValidLatitude(90.1), isFalse);
      expect(isValidLatitude(-90.1), isFalse);
    });
  });

  group('isValidLongitude', () {
    test('accepts in-range values', () {
      expect(isValidLongitude(0), isTrue);
      expect(isValidLongitude(-122.4194), isTrue);
      expect(isValidLongitude(180), isTrue);
      expect(isValidLongitude(-180), isTrue);
    });

    test('rejects NaN and Infinite', () {
      expect(isValidLongitude(double.nan), isFalse);
      expect(isValidLongitude(double.infinity), isFalse);
      expect(isValidLongitude(double.negativeInfinity), isFalse);
    });

    test('rejects out-of-range values', () {
      expect(isValidLongitude(180.1), isFalse);
      expect(isValidLongitude(-180.1), isFalse);
    });
  });

  group('isValidZoom', () {
    test('accepts in-range values (default bounds: 1.0 to kAbsoluteMaxZoom)', () {
      expect(isValidZoom(1), isTrue);
      expect(isValidZoom(15), isTrue);
      expect(isValidZoom(23), isTrue);
    });

    test('rejects NaN and Infinite', () {
      expect(isValidZoom(double.nan), isFalse);
      expect(isValidZoom(double.infinity), isFalse);
      expect(isValidZoom(double.negativeInfinity), isFalse);
    });

    test('rejects out-of-range values with default bounds', () {
      expect(isValidZoom(0), isFalse);
      expect(isValidZoom(0.5), isFalse);
      expect(isValidZoom(24), isFalse);
    });

    test('respects custom min/max bounds', () {
      expect(isValidZoom(0.5, min: 1.0, max: 20.0), isFalse);
      expect(isValidZoom(1.0, min: 1.0, max: 20.0), isTrue);
      expect(isValidZoom(20.0, min: 1.0, max: 20.0), isTrue);
      expect(isValidZoom(20.1, min: 1.0, max: 20.0), isFalse);
    });
  });
}

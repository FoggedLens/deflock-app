import 'package:flutter_test/flutter_test.dart';

import 'package:deflockapp/services/coordinate_validation.dart';

void main() {
  group('isValidCoordinate', () {
    test('accepts normal in-range values', () {
      expect(isValidCoordinate(0), isTrue);
      expect(isValidCoordinate(37.7749), isTrue);
      expect(isValidCoordinate(-122.4194), isTrue);
      expect(isValidCoordinate(180), isTrue);
      expect(isValidCoordinate(-180), isTrue);
    });

    test('rejects NaN', () {
      expect(isValidCoordinate(double.nan), isFalse);
    });

    test('rejects positive and negative infinity', () {
      expect(isValidCoordinate(double.infinity), isFalse);
      expect(isValidCoordinate(double.negativeInfinity), isFalse);
    });

    test('rejects out-of-range values', () {
      expect(isValidCoordinate(180.1), isFalse);
      expect(isValidCoordinate(-180.1), isFalse);
      expect(isValidCoordinate(1000), isFalse);
    });
  });

  group('isValidZoom', () {
    test('accepts normal in-range values', () {
      expect(isValidZoom(0), isTrue);
      expect(isValidZoom(15), isTrue);
      expect(isValidZoom(25), isTrue);
    });

    test('rejects NaN and Infinite', () {
      expect(isValidZoom(double.nan), isFalse);
      expect(isValidZoom(double.infinity), isFalse);
      expect(isValidZoom(double.negativeInfinity), isFalse);
    });

    test('rejects out-of-range values with default bounds', () {
      expect(isValidZoom(-1), isFalse);
      expect(isValidZoom(26), isFalse);
    });

    test('respects custom min/max bounds', () {
      expect(isValidZoom(0.5, min: 1.0, max: 20.0), isFalse);
      expect(isValidZoom(1.0, min: 1.0, max: 20.0), isTrue);
      expect(isValidZoom(20.0, min: 1.0, max: 20.0), isTrue);
      expect(isValidZoom(20.1, min: 1.0, max: 20.0), isFalse);
    });
  });
}

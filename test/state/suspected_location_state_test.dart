import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/models/suspected_location.dart';
import 'package:deflockapp/services/suspected_location_service.dart';
import 'package:deflockapp/state/suspected_location_state.dart';

class MockSuspectedLocationService extends Mock
    implements SuspectedLocationService {}

void main() {
  late MockSuspectedLocationService mockService;
  late SuspectedLocationState state;

  setUp(() {
    mockService = MockSuspectedLocationService();
    state = SuspectedLocationState(service: mockService);
  });

  group('initLocal', () {
    test('calls service initLocal and notifies listeners', () async {
      when(() => mockService.initLocal()).thenAnswer((_) async {});
      when(() => mockService.isEnabled).thenReturn(true);

      var notified = false;
      state.addListener(() => notified = true);

      await state.initLocal();

      verify(() => mockService.initLocal()).called(1);
      expect(notified, isTrue);
      expect(state.isEnabled, isTrue);
    });

    test('catches service errors gracefully', () async {
      when(() => mockService.initLocal())
          .thenThrow(Exception('storage error'));

      await state.initLocal();

      // Should not throw — error is caught and logged
      expect(state.isLoading, isFalse);
    });
  });

  group('refreshIfNeeded', () {
    test('notifies listeners after successful refresh', () async {
      when(() => mockService.refreshIfNeeded(offlineMode: false))
          .thenAnswer((_) async => true);

      var notified = false;
      state.addListener(() => notified = true);

      await state.refreshIfNeeded();

      expect(notified, isTrue);
    });

    test('does not set loading state (avoids fake loading flash)', () async {
      when(() => mockService.refreshIfNeeded(offlineMode: false))
          .thenAnswer((_) async => false);

      final loadingStates = <bool>[];
      state.addListener(() => loadingStates.add(state.isLoading));

      await state.refreshIfNeeded();

      // Should never have been true — no-op refresh shouldn't flash loading
      expect(loadingStates.where((s) => s), isEmpty);
    });

    test('catches service errors without crashing', () async {
      when(() => mockService.refreshIfNeeded(offlineMode: false))
          .thenThrow(Exception('network error'));

      await state.refreshIfNeeded();

      expect(state.isLoading, isFalse);
    });

    test('passes offlineMode through to service', () async {
      when(() => mockService.refreshIfNeeded(offlineMode: true))
          .thenAnswer((_) async => false);

      await state.refreshIfNeeded(offlineMode: true);

      verify(() => mockService.refreshIfNeeded(offlineMode: true)).called(1);
      expect(state.isLoading, isFalse);
    });

    test('clears download progress after refresh', () async {
      when(() => mockService.refreshIfNeeded(offlineMode: false))
          .thenAnswer((_) async => true);

      await state.refreshIfNeeded();

      expect(state.downloadProgress, isNull);
    });
  });

  group('init (full — with network)', () {
    test('calls service.init with offlineMode', () async {
      when(() => mockService.init(offlineMode: true))
          .thenAnswer((_) async {});
      when(() => mockService.isEnabled).thenReturn(false);

      await state.init(offlineMode: true);

      verify(() => mockService.init(offlineMode: true)).called(1);
    });
  });

  group('selection', () {
    test('select sets selected location and notifies', () {
      final location = SuspectedLocation(
        ticketNo: 'T-001',
        centroid: const LatLng(38.9, -77.0),
        bounds: const [],
        allFields: const {},
      );

      var notified = false;
      state.addListener(() => notified = true);

      state.selectLocation(location);

      expect(state.selectedLocation, equals(location));
      expect(notified, isTrue);
    });

    test('clearSelection clears and notifies', () {
      final location = SuspectedLocation(
        ticketNo: 'T-002',
        centroid: const LatLng(38.9, -77.0),
        bounds: const [],
        allFields: const {},
      );

      state.selectLocation(location);
      expect(state.selectedLocation, isNotNull);

      var notified = false;
      state.addListener(() => notified = true);

      state.clearSelection();

      expect(state.selectedLocation, isNull);
      expect(notified, isTrue);
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

import 'package:deflockapp/models/rf_detection.dart';
import 'package:deflockapp/services/rf_detection_database.dart';
import 'package:deflockapp/services/scanner_service.dart';
import 'package:deflockapp/state/scanner_state.dart';
import '../fixtures/serial_json_fixtures.dart';

/// Pump the microtask queue to let async stream handlers complete.
/// Each `Future.delayed(Duration.zero)` yields once to the event loop;
/// repeating ensures multi-await handlers like `_onDetectionEvent` settle.
Future<void> pumpEventQueue({int times = 20}) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------
class MockScannerService extends Mock implements ScannerService {}

class MockRfDetectionDatabase extends Mock implements RfDetectionDatabase {}

class FakeRfDetection extends Fake implements RfDetection {}

class FakeRfSighting extends Fake implements RfSighting {}

/// Test subclass that overrides GPS to avoid hardware dependency.
class TestableScannerState extends ScannerState {
  Position? stubbedPosition;

  TestableScannerState({
    required ScannerService scanner,
    required RfDetectionDatabase db,
  }) : super(scanner: scanner, db: db);

  @override
  Future<Position?> getLastKnownPosition() async => stubbedPosition;
}

Position _fakePosition({
  double lat = 45.0,
  double lng = -93.0,
  double accuracy = 5.0,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  late MockScannerService mockScanner;
  late MockRfDetectionDatabase mockDb;
  late TestableScannerState state;
  late StreamController<Map<String, dynamic>> eventController;
  late StreamController<ScannerConnectionStatus> statusController;

  setUpAll(() {
    registerFallbackValue(FakeRfDetection());
    registerFallbackValue(FakeRfSighting());
  });

  setUp(() {
    mockScanner = MockScannerService();
    mockDb = MockRfDetectionDatabase();
    eventController = StreamController<Map<String, dynamic>>.broadcast();
    statusController = StreamController<ScannerConnectionStatus>.broadcast();

    when(() => mockScanner.events).thenAnswer((_) => eventController.stream);
    when(() => mockScanner.statusStream)
        .thenAnswer((_) => statusController.stream);
    when(() => mockScanner.status)
        .thenReturn(ScannerConnectionStatus.disconnected);
    when(() => mockScanner.isConnected).thenReturn(false);
    when(() => mockScanner.lastError).thenReturn(null);

    state = TestableScannerState(scanner: mockScanner, db: mockDb);
    state.stubbedPosition = _fakePosition();
  });

  tearDown(() async {
    eventController.close();
    statusController.close();
  });

  /// Call init() with mocked DB/scanner prerequisites.
  /// This subscribes state to event and status streams.
  Future<void> initState({int initialCount = 0}) async {
    when(() => mockDb.init()).thenAnswer((_) async {});
    when(() => mockDb.getStats()).thenAnswer((_) async => {
          'total': initialCount,
          'submitted': 0,
          'unsubmitted': initialCount,
          'byAlertLevel': <int, int>{},
        });
    when(() => mockScanner.init()).thenAnswer((_) async {});
    await state.init();
  }

  // ---------------------------------------------------------------------------
  // Detection processing
  // ---------------------------------------------------------------------------
  group('Detection processing', () {
    test('creates RfDetection and RfSighting from event', () async {
      when(() => mockDb.upsertDetection(any())).thenAnswer((_) async {});
      when(() => mockDb.addSighting(any())).thenAnswer((_) async {});
      await initState();

      eventController.add(makeDetectionJson());
      await pumpEventQueue();

      verify(() => mockDb.upsertDetection(any())).called(1);
      verify(() => mockDb.addSighting(any())).called(1);
    });

    test('inserts detection at head of recentDetections', () async {
      when(() => mockDb.upsertDetection(any())).thenAnswer((_) async {});
      when(() => mockDb.addSighting(any())).thenAnswer((_) async {});
      await initState();

      eventController.add(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:01'));
      await pumpEventQueue();

      eventController.add(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:02'));
      await pumpEventQueue();

      expect(state.recentDetections, hasLength(2));
      expect(state.recentDetections[0].mac, 'aa:aa:aa:aa:aa:02');
      expect(state.recentDetections[1].mac, 'aa:aa:aa:aa:aa:01');
    });

    test('increments detection count', () async {
      when(() => mockDb.upsertDetection(any())).thenAnswer((_) async {});
      when(() => mockDb.addSighting(any())).thenAnswer((_) async {});
      await initState();

      final initial = state.detectionCount;
      eventController.add(makeDetectionJson());
      await pumpEventQueue();

      expect(state.detectionCount, initial + 1);
    });

    test('notifies listeners on detection', () async {
      when(() => mockDb.upsertDetection(any())).thenAnswer((_) async {});
      when(() => mockDb.addSighting(any())).thenAnswer((_) async {});
      await initState();

      var notified = false;
      state.addListener(() => notified = true);

      eventController.add(makeDetectionJson());
      await pumpEventQueue();

      expect(notified, isTrue);
    });

    test('skips detection when GPS is null', () async {
      await initState();
      state.stubbedPosition = null;

      eventController.add(makeDetectionJson());
      await pumpEventQueue();

      verifyNever(() => mockDb.upsertDetection(any()));
      verifyNever(() => mockDb.addSighting(any()));
      expect(state.recentDetections, isEmpty);
    });

    test('no increment or list change when GPS is null', () async {
      await initState();
      state.stubbedPosition = null;
      final initialCount = state.detectionCount;

      eventController.add(makeDetectionJson());
      await pumpEventQueue();

      expect(state.detectionCount, initialCount);
      expect(state.recentDetections, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Recent list management
  // ---------------------------------------------------------------------------
  group('Recent list management', () {
    setUp(() {
      when(() => mockDb.upsertDetection(any())).thenAnswer((_) async {});
      when(() => mockDb.addSighting(any())).thenAnswer((_) async {});
    });

    test('caps at 50 detections', () async {
      await initState();
      for (var i = 0; i < 55; i++) {
        eventController.add(makeDetectionJson(
            mac:
                'AA:AA:AA:AA:${(i ~/ 256).toRadixString(16).padLeft(2, '0')}:${(i % 256).toRadixString(16).padLeft(2, '0')}'));
        await pumpEventQueue();
      }

      expect(state.recentDetections.length, lessThanOrEqualTo(50));
    });

    test('removes oldest when list exceeds 50', () async {
      await initState();
      for (var i = 0; i < 51; i++) {
        eventController.add(makeDetectionJson(
            mac:
                'AA:AA:AA:AA:${(i ~/ 256).toRadixString(16).padLeft(2, '0')}:${(i % 256).toRadixString(16).padLeft(2, '0')}'));
        await pumpEventQueue();
      }

      expect(state.recentDetections.length, 50);
      // First detection (MAC ending 00:00) should have been evicted
      expect(
          state.recentDetections.any((d) => d.mac == 'aa:aa:aa:aa:00:00'),
          isFalse);
    });

    test('maintains newest-first order', () async {
      await initState();
      for (var i = 0; i < 3; i++) {
        eventController.add(makeDetectionJson(
            mac:
                'AA:AA:AA:AA:AA:${i.toRadixString(16).padLeft(2, '0')}'));
        await pumpEventQueue();
      }

      expect(state.recentDetections.length, 3);
      // Most recent (i=2) should be first
      expect(state.recentDetections[0].mac, 'aa:aa:aa:aa:aa:02');
    });
  });

  // ---------------------------------------------------------------------------
  // Deletion
  // ---------------------------------------------------------------------------
  group('Deletion', () {
    test('calls DB deleteDetection', () async {
      when(() => mockDb.deleteDetection(any())).thenAnswer((_) async {});
      await state.deleteDetection('aa:bb:cc:dd:ee:ff');
      verify(() => mockDb.deleteDetection('aa:bb:cc:dd:ee:ff')).called(1);
    });

    test('removes from recent list by MAC', () async {
      when(() => mockDb.upsertDetection(any())).thenAnswer((_) async {});
      when(() => mockDb.addSighting(any())).thenAnswer((_) async {});
      when(() => mockDb.deleteDetection(any())).thenAnswer((_) async {});
      await initState();

      eventController.add(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:01'));
      await pumpEventQueue();
      eventController.add(makeDetectionJson(mac: 'AA:AA:AA:AA:AA:02'));
      await pumpEventQueue();

      expect(state.recentDetections, hasLength(2));

      await state.deleteDetection('aa:aa:aa:aa:aa:01');
      expect(
          state.recentDetections.any((d) => d.mac == 'aa:aa:aa:aa:aa:01'),
          isFalse);
      expect(state.recentDetections, hasLength(1));
    });

    test('decrements detection count', () async {
      when(() => mockDb.upsertDetection(any())).thenAnswer((_) async {});
      when(() => mockDb.addSighting(any())).thenAnswer((_) async {});
      when(() => mockDb.deleteDetection(any())).thenAnswer((_) async {});
      await initState();

      eventController.add(makeDetectionJson());
      await pumpEventQueue();
      final countBefore = state.detectionCount;

      await state.deleteDetection('b4:1e:52:aa:bb:cc');
      expect(state.detectionCount, countBefore - 1);
    });

    test('notifies listeners on delete', () async {
      when(() => mockDb.deleteDetection(any())).thenAnswer((_) async {});

      var notified = false;
      state.addListener(() => notified = true);
      await state.deleteDetection('aa:bb:cc:dd:ee:ff');

      expect(notified, isTrue);
    });

    test('handles deletion of MAC not in recent list', () async {
      when(() => mockDb.deleteDetection(any())).thenAnswer((_) async {});

      // Should not throw
      await state.deleteDetection('ff:ff:ff:ff:ff:ff');
      verify(() => mockDb.deleteDetection('ff:ff:ff:ff:ff:ff')).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Connection status
  // ---------------------------------------------------------------------------
  group('Connection status', () {
    test('initial status is disconnected', () {
      expect(state.connectionStatus, ScannerConnectionStatus.disconnected);
    });

    test('forwards status changes from scanner', () async {
      await initState();

      var notified = false;
      state.addListener(() => notified = true);

      statusController.add(ScannerConnectionStatus.connected);
      await pumpEventQueue();

      expect(state.connectionStatus, ScannerConnectionStatus.connected);
      expect(notified, isTrue);
    });

    test('delegates isConnected to scanner', () {
      when(() => mockScanner.isConnected).thenReturn(true);
      expect(state.isConnected, isTrue);

      when(() => mockScanner.isConnected).thenReturn(false);
      expect(state.isConnected, isFalse);
    });

    test('delegates lastError to scanner', () {
      when(() => mockScanner.lastError).thenReturn('test error');
      expect(state.lastError, 'test error');

      when(() => mockScanner.lastError).thenReturn(null);
      expect(state.lastError, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Transport type
  // ---------------------------------------------------------------------------
  group('Transport type', () {
    test('defaults to BLE when using single-scanner constructor', () {
      // TestableScannerState is constructed with scanner: param which means
      // _usbScanner is null — activeTransportType should always be BLE.
      expect(state.activeTransportType, ScannerTransportType.ble);
    });

    test('remains BLE after init', () async {
      await initState();
      expect(state.activeTransportType, ScannerTransportType.ble);
    });

    test('remains BLE after status changes', () async {
      await initState();
      statusController.add(ScannerConnectionStatus.connected);
      await pumpEventQueue();
      expect(state.activeTransportType, ScannerTransportType.ble);
    });
  });

  // ---------------------------------------------------------------------------
  // DB passthrough
  // ---------------------------------------------------------------------------
  group('DB passthrough', () {
    test('getDetections delegates to DB', () async {
      when(() => mockDb.getDetections(
            minAlertLevel: any(named: 'minAlertLevel'),
            hasOsmNode: any(named: 'hasOsmNode'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => <RfDetection>[]);

      await state.getDetections(minAlertLevel: 3, limit: 10);
      verify(() => mockDb.getDetections(
            minAlertLevel: 3,
            hasOsmNode: null,
            limit: 10,
          )).called(1);
    });

    test('getDetectionsInBounds delegates to DB', () async {
      when(() => mockDb.getDetectionsInBounds(
            north: any(named: 'north'),
            south: any(named: 'south'),
            east: any(named: 'east'),
            west: any(named: 'west'),
          )).thenAnswer((_) async => <RfDetection>[]);

      await state.getDetectionsInBounds(
        north: 46.0,
        south: 44.0,
        east: -92.0,
        west: -94.0,
      );
      verify(() => mockDb.getDetectionsInBounds(
            north: 46.0,
            south: 44.0,
            east: -92.0,
            west: -94.0,
          )).called(1);
    });

    test('getSightingsForMac delegates to DB', () async {
      when(() => mockDb.getSightingsForMac(any()))
          .thenAnswer((_) async => <RfSighting>[]);

      await state.getSightingsForMac('aa:bb:cc:dd:ee:ff');
      verify(() => mockDb.getSightingsForMac('aa:bb:cc:dd:ee:ff')).called(1);
    });

    test('linkDetectionToNode delegates to DB', () async {
      when(() => mockDb.linkToOsmNode(any(), any())).thenAnswer((_) async {});

      await state.linkDetectionToNode('aa:bb:cc:dd:ee:ff', 12345);
      verify(() => mockDb.linkToOsmNode('aa:bb:cc:dd:ee:ff', 12345)).called(1);
    });

    test('getStats delegates to DB', () async {
      when(() => mockDb.getStats()).thenAnswer((_) async => {
            'total': 0,
            'submitted': 0,
            'unsubmitted': 0,
            'byAlertLevel': <int, int>{},
          });

      await state.getStats();
      verify(() => mockDb.getStats()).called(1);
    });
  });

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------
  group('Init', () {
    test('initializes DB, loads count, subscribes to streams, starts scanner',
        () async {
      await initState(initialCount: 42);

      verify(() => mockDb.init()).called(1);
      verify(() => mockDb.getStats()).called(1);
      verify(() => mockScanner.init()).called(1);
      expect(state.detectionCount, 42);
    });

    test('notifies listeners after init', () async {
      var notified = false;
      state.addListener(() => notified = true);
      await initState();

      expect(notified, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------
  group('Dispose', () {
    test('cancels subscriptions and disposes resources', () async {
      when(() => mockScanner.dispose()).thenAnswer((_) async {});
      when(() => mockDb.close()).thenAnswer((_) async {});

      state.dispose();

      verify(() => mockScanner.dispose()).called(1);
      verify(() => mockDb.close()).called(1);
    });
  });
}

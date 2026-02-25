import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:deflockapp/models/rf_detection.dart';
import 'package:deflockapp/services/rf_detection_database.dart';
import '../fixtures/serial_json_fixtures.dart';

/// Open a fresh in-memory SQLite database with the RF detection schema.
Future<RfDetectionDatabase> _freshDb() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1),
  );
  RfDetectionDatabase.resetForTesting(database: db);
  await RfDetectionDatabase.createTablesForTesting(db);
  return RfDetectionDatabase();
}

/// Build an RfDetection from serial JSON defaults with overrides.
RfDetection _makeDetection({
  String mac = 'b4:1e:52:aa:bb:cc',
  String label = 'Flock-a1b2c3',
  String radio = 'WiFi',
  int alertLevel = 3,
  int certainty = 90,
  String category = 'flock_safety_camera',
  Map<String, int>? detectors,
  DateTime? now,
}) {
  final json = makeDetectionJson(
    mac: mac,
    label: label,
    radio: radio,
    alertLevel: alertLevel,
    certainty: certainty,
    category: category,
    detectors: detectors ?? {'ssid_format': 75, 'flock_oui': 90},
  );
  return RfDetection.fromSerialJson(
    json,
    LatLng(45.0, -93.0),
    now ?? DateTime(2025, 6, 1),
  );
}

/// Build an RfSighting from serial JSON defaults.
RfSighting _makeSighting({
  String mac = 'b4:1e:52:aa:bb:cc',
  double lat = 45.0,
  double lng = -93.0,
  int rssi = -55,
  int channel = 6,
  DateTime? now,
}) {
  final json = makeDetectionJson(mac: mac, rssi: rssi, channel: channel);
  return RfSighting.fromSerialJson(
    json,
    LatLng(lat, lng),
    5.0,
    now ?? DateTime(2025, 6, 1),
  );
}

void main() {
  // Use FFI for desktop test runner
  sqfliteFfiInit();

  late RfDetectionDatabase rfDb;

  setUp(() async {
    rfDb = await _freshDb();
  });

  tearDown(() async {
    await rfDb.close();
  });

  // ---------------------------------------------------------------------------
  // Table creation
  // ---------------------------------------------------------------------------
  group('Table creation', () {
    test('rf_devices table exists with expected columns', () async {
      final db = await rfDb.database;
      final info = await db.rawQuery("PRAGMA table_info('rf_devices')");
      final columns = info.map((r) => r['name'] as String).toSet();
      expect(
        columns,
        containsAll([
          'mac',
          'oui',
          'label',
          'radio_type',
          'category',
          'alert_level',
          'max_certainty',
          'match_flags',
          'detector_data',
          'ssid',
          'ble_name',
          'ble_service_uuids',
          'osm_node_id',
          'first_seen_at',
          'last_seen_at',
          'sighting_count',
          'notes',
        ]),
      );
    });

    test('rf_sightings table exists with expected columns', () async {
      final db = await rfDb.database;
      final info = await db.rawQuery("PRAGMA table_info('rf_sightings')");
      final columns = info.map((r) => r['name'] as String).toSet();
      expect(
        columns,
        containsAll([
          'id',
          'mac',
          'lat',
          'lng',
          'gps_accuracy',
          'rssi',
          'channel',
          'seen_at',
          'raw_json',
        ]),
      );
    });

    test('indexes exist', () async {
      final db = await rfDb.database;
      final indexes = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index'");
      final names = indexes.map((r) => r['name'] as String).toSet();
      expect(names, contains('idx_rf_devices_oui'));
      expect(names, contains('idx_rf_devices_alert'));
      expect(names, contains('idx_rf_devices_osm'));
      expect(names, contains('idx_sightings_mac'));
      expect(names, contains('idx_sightings_lat_lng'));
      expect(names, contains('idx_sightings_seen'));
    });

    test('metadata table has schema_version', () async {
      final db = await rfDb.database;
      final rows = await db.query('metadata',
          where: "key = ?", whereArgs: ['schema_version']);
      expect(rows, hasLength(1));
      expect(rows.first['value'], '1');
    });
  });

  // ---------------------------------------------------------------------------
  // upsertDetection — insert
  // ---------------------------------------------------------------------------
  group('upsertDetection — insert', () {
    test('new MAC is inserted and retrievable', () async {
      final d = _makeDetection();
      await rfDb.upsertDetection(d);

      final results = await rfDb.getDetections();
      expect(results, hasLength(1));
      expect(results.first.mac, d.mac);
    });

    test('all fields preserved on insert', () async {
      final d = _makeDetection();
      await rfDb.upsertDetection(d);

      final results = await rfDb.getDetections();
      final r = results.first;
      expect(r.oui, d.oui);
      expect(r.label, d.label);
      expect(r.radioType, d.radioType);
      expect(r.category, d.category);
      expect(r.alertLevel, d.alertLevel);
      expect(r.maxCertainty, d.maxCertainty);
      expect(r.matchFlags, d.matchFlags);
      expect(r.detectorData, d.detectorData);
      expect(r.ssid, d.ssid);
      expect(r.sightingCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // upsertDetection — merge
  // ---------------------------------------------------------------------------
  group('upsertDetection — merge', () {
    test('alert level escalates upward', () async {
      await rfDb.upsertDetection(_makeDetection(alertLevel: 2));
      await rfDb.upsertDetection(_makeDetection(alertLevel: 4));

      final results = await rfDb.getDetections();
      expect(results.first.alertLevel, 4);
    });

    test('alert level does not decrease', () async {
      await rfDb.upsertDetection(_makeDetection(alertLevel: 4));
      await rfDb.upsertDetection(_makeDetection(alertLevel: 1));

      final results = await rfDb.getDetections();
      expect(results.first.alertLevel, 4);
    });

    test('certainty escalates upward', () async {
      await rfDb.upsertDetection(_makeDetection(certainty: 50));
      await rfDb.upsertDetection(_makeDetection(certainty: 95));

      final results = await rfDb.getDetections();
      expect(results.first.maxCertainty, 95);
    });

    test('certainty does not decrease', () async {
      await rfDb.upsertDetection(_makeDetection(certainty: 95));
      await rfDb.upsertDetection(_makeDetection(certainty: 50));

      final results = await rfDb.getDetections();
      expect(results.first.maxCertainty, 95);
    });

    test('matchFlags are OR-merged', () async {
      await rfDb.upsertDetection(
          _makeDetection(detectors: {'ssid_format': 50})); // bit 0
      await rfDb.upsertDetection(
          _makeDetection(detectors: {'flock_oui': 80})); // bit 7

      final results = await rfDb.getDetections();
      expect(results.first.matchFlags, (1 << 0) | (1 << 7));
    });

    test('detectorData merges keeping highest weight', () async {
      await rfDb
          .upsertDetection(_makeDetection(detectors: {'ssid_format': 50}));
      await rfDb
          .upsertDetection(_makeDetection(detectors: {'ssid_format': 90}));

      final results = await rfDb.getDetections();
      expect(results.first.detectorData['ssid_format'], 90);
    });

    test('detectorData merges new keys', () async {
      await rfDb
          .upsertDetection(_makeDetection(detectors: {'ssid_format': 50}));
      await rfDb
          .upsertDetection(_makeDetection(detectors: {'flock_oui': 80}));

      final results = await rfDb.getDetections();
      expect(results.first.detectorData['ssid_format'], 50);
      expect(results.first.detectorData['flock_oui'], 80);
    });

    test('detectorData preserves existing keys with higher weight', () async {
      await rfDb
          .upsertDetection(_makeDetection(detectors: {'ssid_format': 90}));
      await rfDb
          .upsertDetection(_makeDetection(detectors: {'ssid_format': 50}));

      final results = await rfDb.getDetections();
      expect(results.first.detectorData['ssid_format'], 90);
    });

    test('label updates when new is more specific (non-MAC)', () async {
      // First insert with MAC as label
      await rfDb.upsertDetection(
          _makeDetection(label: 'b4:1e:52:aa:bb:cc'));
      // Second with a real name
      await rfDb.upsertDetection(_makeDetection(label: 'Flock-a1b2c3'));

      final results = await rfDb.getDetections();
      expect(results.first.label, 'Flock-a1b2c3');
    });

    test('lastSeenAt updates', () async {
      final t1 = DateTime(2025, 1, 1);
      final t2 = DateTime(2025, 6, 1);
      await rfDb.upsertDetection(_makeDetection(now: t1));
      await rfDb.upsertDetection(_makeDetection(now: t2));

      final results = await rfDb.getDetections();
      expect(results.first.lastSeenAt, t2);
    });

    test('firstSeenAt preserved', () async {
      final t1 = DateTime(2025, 1, 1);
      final t2 = DateTime(2025, 6, 1);
      await rfDb.upsertDetection(_makeDetection(now: t1));
      await rfDb.upsertDetection(_makeDetection(now: t2));

      final results = await rfDb.getDetections();
      expect(results.first.firstSeenAt, t1);
    });

    test('sightingCount increments', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.upsertDetection(_makeDetection());

      final results = await rfDb.getDetections();
      expect(results.first.sightingCount, 3);
    });

    test('ssid merged when newly available', () async {
      // First insert without ssid
      final d1 = RfDetection(
        mac: 'aa:bb:cc:dd:ee:ff',
        oui: 'aa:bb:cc',
        label: 'aa:bb:cc:dd:ee:ff',
        radioType: 'WiFi',
        category: 'unknown',
        alertLevel: 0,
        maxCertainty: 0,
        matchFlags: 0,
        detectorData: {},
        firstSeenAt: DateTime(2025, 1, 1),
        lastSeenAt: DateTime(2025, 1, 1),
      );
      await rfDb.upsertDetection(d1);

      // Second upsert with ssid populated
      final d2 = RfDetection(
        mac: 'aa:bb:cc:dd:ee:ff',
        oui: 'aa:bb:cc',
        label: 'NewSSID',
        radioType: 'WiFi',
        category: 'unknown',
        alertLevel: 0,
        maxCertainty: 0,
        matchFlags: 0,
        detectorData: {},
        ssid: 'NewSSID',
        firstSeenAt: DateTime(2025, 1, 1),
        lastSeenAt: DateTime(2025, 6, 1),
      );
      await rfDb.upsertDetection(d2);

      final results = await rfDb.getDetections();
      expect(results.first.ssid, 'NewSSID');
    });

    test('multiple upserts accumulate correctly', () async {
      // 5 upserts with increasing certainty
      for (var i = 1; i <= 5; i++) {
        await rfDb.upsertDetection(_makeDetection(certainty: i * 20));
      }

      final results = await rfDb.getDetections();
      expect(results, hasLength(1));
      expect(results.first.sightingCount, 5);
      expect(results.first.maxCertainty, 100);
    });
  });

  // ---------------------------------------------------------------------------
  // addSighting
  // ---------------------------------------------------------------------------
  group('addSighting', () {
    test('inserts sighting', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.addSighting(_makeSighting());

      final sightings = await rfDb.getSightingsForMac('b4:1e:52:aa:bb:cc');
      expect(sightings, hasLength(1));
    });

    test('auto-increments ID', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.addSighting(_makeSighting());
      await rfDb.addSighting(_makeSighting());

      final sightings = await rfDb.getSightingsForMac('b4:1e:52:aa:bb:cc');
      expect(sightings[0].id, isNot(sightings[1].id));
    });

    test('MAC association correct', () async {
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.addSighting(_makeSighting(mac: 'AA:AA:AA:AA:AA:01'));

      final s1 = await rfDb.getSightingsForMac('aa:aa:aa:aa:aa:01');
      final s2 = await rfDb.getSightingsForMac('aa:aa:aa:aa:aa:02');
      expect(s1, hasLength(1));
      expect(s2, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // getDetections
  // ---------------------------------------------------------------------------
  group('getDetections', () {
    test('returns results ordered by last_seen DESC', () async {
      await rfDb.upsertDetection(_makeDetection(
          mac: 'AA:AA:AA:AA:AA:01', now: DateTime(2025, 1, 1)));
      await rfDb.upsertDetection(_makeDetection(
          mac: 'AA:AA:AA:AA:AA:02', now: DateTime(2025, 6, 1)));

      final results = await rfDb.getDetections();
      expect(results, hasLength(2));
      expect(results[0].mac, 'aa:aa:aa:aa:aa:02'); // newer first
      expect(results[1].mac, 'aa:aa:aa:aa:aa:01');
    });

    test('minAlertLevel filter', () async {
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:01', alertLevel: 1));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:02', alertLevel: 3));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:03', alertLevel: 5));

      final results = await rfDb.getDetections(minAlertLevel: 3);
      expect(results, hasLength(2));
      expect(results.every((d) => d.alertLevel >= 3), isTrue);
    });

    test('hasOsmNode true filter', () async {
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.linkToOsmNode('aa:aa:aa:aa:aa:01', 999);

      final results = await rfDb.getDetections(hasOsmNode: true);
      expect(results, hasLength(1));
      expect(results.first.mac, 'aa:aa:aa:aa:aa:01');
    });

    test('hasOsmNode false filter', () async {
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.linkToOsmNode('aa:aa:aa:aa:aa:01', 999);

      final results = await rfDb.getDetections(hasOsmNode: false);
      expect(results, hasLength(1));
      expect(results.first.mac, 'aa:aa:aa:aa:aa:02');
    });

    test('limit constrains result count', () async {
      for (var i = 0; i < 10; i++) {
        await rfDb.upsertDetection(_makeDetection(
            mac: 'AA:AA:AA:AA:${i.toString().padLeft(2, '0')}:00'));
      }

      final results = await rfDb.getDetections(limit: 3);
      expect(results, hasLength(3));
    });

    test('bestPosition joined from latest sighting', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.addSighting(
          _makeSighting(lat: 44.0, lng: -92.0));

      final results = await rfDb.getDetections();
      expect(results.first.bestPosition, isNotNull);
      expect(results.first.bestPosition!.latitude, 44.0);
      expect(results.first.bestPosition!.longitude, -92.0);
    });

    test('no sightings = null bestPosition', () async {
      await rfDb.upsertDetection(_makeDetection());

      final results = await rfDb.getDetections();
      expect(results.first.bestPosition, isNull);
    });

    test('combined filters work together', () async {
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:01', alertLevel: 1));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:02', alertLevel: 3));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:03', alertLevel: 5));
      await rfDb.linkToOsmNode('aa:aa:aa:aa:aa:03', 999);

      // Alert >= 3 AND no OSM node
      final results =
          await rfDb.getDetections(minAlertLevel: 3, hasOsmNode: false);
      expect(results, hasLength(1));
      expect(results.first.mac, 'aa:aa:aa:aa:aa:02');
    });

    test('empty DB returns empty list', () async {
      final results = await rfDb.getDetections();
      expect(results, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // getDetectionsInBounds
  // ---------------------------------------------------------------------------
  group('getDetectionsInBounds', () {
    test('in-bounds detection returned', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.addSighting(_makeSighting(lat: 45.0, lng: -93.0));

      final results = await rfDb.getDetectionsInBounds(
        north: 46.0,
        south: 44.0,
        east: -92.0,
        west: -94.0,
      );
      expect(results, hasLength(1));
    });

    test('out-of-bounds detection excluded', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.addSighting(_makeSighting(lat: 45.0, lng: -93.0));

      final results = await rfDb.getDetectionsInBounds(
        north: 10.0,
        south: 9.0,
        east: 10.0,
        west: 9.0,
      );
      expect(results, isEmpty);
    });

    test('INNER JOIN excludes devices without sightings', () async {
      await rfDb.upsertDetection(_makeDetection());
      // No sighting added

      final results = await rfDb.getDetectionsInBounds(
        north: 90.0,
        south: -90.0,
        east: 180.0,
        west: -180.0,
      );
      expect(results, isEmpty);
    });

    test('ordered by alert_level DESC', () async {
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:01', alertLevel: 1));
      await rfDb.addSighting(_makeSighting(
          mac: 'AA:AA:AA:AA:AA:01', lat: 45.0, lng: -93.0));

      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:02', alertLevel: 5));
      await rfDb.addSighting(_makeSighting(
          mac: 'AA:AA:AA:AA:AA:02', lat: 45.1, lng: -93.1));

      final results = await rfDb.getDetectionsInBounds(
        north: 46.0,
        south: 44.0,
        east: -92.0,
        west: -94.0,
      );
      expect(results, hasLength(2));
      expect(results[0].alertLevel, 5); // higher first
      expect(results[1].alertLevel, 1);
    });

    test('uses latest sighting position', () async {
      await rfDb.upsertDetection(_makeDetection());
      // Old sighting outside bounds
      await rfDb.addSighting(_makeSighting(lat: 0.0, lng: 0.0));
      // Newer sighting inside bounds
      await rfDb.addSighting(_makeSighting(lat: 45.0, lng: -93.0));

      final results = await rfDb.getDetectionsInBounds(
        north: 46.0,
        south: 44.0,
        east: -92.0,
        west: -94.0,
      );
      // Uses MAX(id) which is the latest sighting (in bounds)
      expect(results, hasLength(1));
      expect(results.first.bestPosition!.latitude, 45.0);
    });
  });

  // ---------------------------------------------------------------------------
  // getSightingsForMac
  // ---------------------------------------------------------------------------
  group('getSightingsForMac', () {
    test('returns sightings for correct MAC', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.addSighting(_makeSighting());
      await rfDb.addSighting(_makeSighting());

      final sightings = await rfDb.getSightingsForMac('b4:1e:52:aa:bb:cc');
      expect(sightings, hasLength(2));
    });

    test('returns empty for unknown MAC', () async {
      final sightings = await rfDb.getSightingsForMac('ff:ff:ff:ff:ff:ff');
      expect(sightings, isEmpty);
    });

    test('no cross-contamination between MACs', () async {
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.addSighting(_makeSighting(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.addSighting(_makeSighting(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.addSighting(_makeSighting(mac: 'AA:AA:AA:AA:AA:02'));

      final s1 = await rfDb.getSightingsForMac('aa:aa:aa:aa:aa:01');
      final s2 = await rfDb.getSightingsForMac('aa:aa:aa:aa:aa:02');
      expect(s1, hasLength(2));
      expect(s2, hasLength(1));
    });
  });

  // ---------------------------------------------------------------------------
  // linkToOsmNode
  // ---------------------------------------------------------------------------
  group('linkToOsmNode', () {
    test('sets osmNodeId', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.linkToOsmNode('b4:1e:52:aa:bb:cc', 12345);

      final results = await rfDb.getDetections();
      expect(results.first.osmNodeId, 12345);
    });

    test('isSubmitted becomes true', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.linkToOsmNode('b4:1e:52:aa:bb:cc', 12345);

      final results = await rfDb.getDetections();
      expect(results.first.isSubmitted, isTrue);
    });

    test('no side effects on other devices', () async {
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.linkToOsmNode('aa:aa:aa:aa:aa:01', 999);

      final results = await rfDb.getDetections();
      final other = results.firstWhere((d) => d.mac == 'aa:aa:aa:aa:aa:02');
      expect(other.osmNodeId, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // getUnsubmittedDetections
  // ---------------------------------------------------------------------------
  group('getUnsubmittedDetections', () {
    test('returns only devices with null osmNodeId', () async {
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.linkToOsmNode('aa:aa:aa:aa:aa:01', 999);

      final results = await rfDb.getUnsubmittedDetections();
      expect(results, hasLength(1));
      expect(results.first.mac, 'aa:aa:aa:aa:aa:02');
    });
  });

  // ---------------------------------------------------------------------------
  // deleteDetection
  // ---------------------------------------------------------------------------
  group('deleteDetection', () {
    test('removes device and its sightings', () async {
      await rfDb.upsertDetection(_makeDetection());
      await rfDb.addSighting(_makeSighting());
      await rfDb.deleteDetection('b4:1e:52:aa:bb:cc');

      final detections = await rfDb.getDetections();
      final sightings = await rfDb.getSightingsForMac('b4:1e:52:aa:bb:cc');
      expect(detections, isEmpty);
      expect(sightings, isEmpty);
    });

    test('no side effects on other devices', () async {
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.addSighting(_makeSighting(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.addSighting(_makeSighting(mac: 'AA:AA:AA:AA:AA:02'));

      await rfDb.deleteDetection('aa:aa:aa:aa:aa:01');

      final detections = await rfDb.getDetections();
      expect(detections, hasLength(1));
      expect(detections.first.mac, 'aa:aa:aa:aa:aa:02');

      final sightings = await rfDb.getSightingsForMac('aa:aa:aa:aa:aa:02');
      expect(sightings, hasLength(1));
    });

    test('idempotent for missing MAC', () async {
      // Should not throw
      await rfDb.deleteDetection('ff:ff:ff:ff:ff:ff');
      final detections = await rfDb.getDetections();
      expect(detections, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // getStats
  // ---------------------------------------------------------------------------
  group('getStats', () {
    test('total, submitted, unsubmitted counts', () async {
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:01'));
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:02'));
      await rfDb.upsertDetection(_makeDetection(mac: 'AA:AA:AA:AA:AA:03'));
      await rfDb.linkToOsmNode('aa:aa:aa:aa:aa:01', 111);

      final stats = await rfDb.getStats();
      expect(stats['total'], 3);
      expect(stats['submitted'], 1);
      expect(stats['unsubmitted'], 2);
    });

    test('byAlertLevel breakdown', () async {
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:01', alertLevel: 1));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:02', alertLevel: 3));
      await rfDb.upsertDetection(
          _makeDetection(mac: 'AA:AA:AA:AA:AA:03', alertLevel: 3));

      final stats = await rfDb.getStats();
      final byAlert = stats['byAlertLevel'] as Map<int, int>;
      expect(byAlert[1], 1);
      expect(byAlert[3], 2);
    });

    test('empty DB returns zeros', () async {
      final stats = await rfDb.getStats();
      expect(stats['total'], 0);
      expect(stats['submitted'], 0);
      expect(stats['unsubmitted'], 0);
      expect((stats['byAlertLevel'] as Map), isEmpty);
    });
  });
}

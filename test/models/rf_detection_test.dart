import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:deflockapp/models/rf_detection.dart';
import '../fixtures/serial_json_fixtures.dart';

void main() {
  // ---------------------------------------------------------------------------
  // RfDetection.fromSerialJson
  // ---------------------------------------------------------------------------
  group('RfDetection.fromSerialJson', () {
    final gps = LatLng(45.0, -93.0);
    final now = DateTime(2025, 6, 1, 12, 0, 0);

    test('parses WiFi detection with all fields', () {
      final json = makeDetectionJson();
      final d = RfDetection.fromSerialJson(json, gps, now);

      expect(d.mac, 'b4:1e:52:aa:bb:cc');
      expect(d.oui, 'b4:1e:52');
      expect(d.label, 'Flock-a1b2c3');
      expect(d.radioType, 'WiFi');
      expect(d.category, 'flock_safety_camera');
      expect(d.alertLevel, 3);
      expect(d.maxCertainty, 90);
      expect(d.firstSeenAt, now);
      expect(d.lastSeenAt, now);
      expect(d.sightingCount, 1);
      expect(d.bestPosition, gps);
    });

    test('parses BLE detection', () {
      final json = makeDetectionJson(
        radio: 'BLE',
        mac: 'AA:BB:CC:DD:EE:FF',
        label: 'Raven-XY',
        category: 'body_camera',
        detectors: {'ble_name': 80},
      );
      final d = RfDetection.fromSerialJson(json, gps, now);

      expect(d.radioType, 'BLE');
      expect(d.bleName, 'Raven-XY');
      expect(d.ssid, isNull);
    });

    test('lowercases MAC address', () {
      final json = makeDetectionJson(mac: 'B4:1E:52:AA:BB:CC');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.mac, 'b4:1e:52:aa:bb:cc');
    });

    test('extracts OUI (first 8 chars) from MAC', () {
      final json = makeDetectionJson(mac: 'AA:BB:CC:11:22:33');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.oui, 'aa:bb:cc');
    });

    test('sets ssid for WiFi, not for BLE', () {
      final wifi = RfDetection.fromSerialJson(
        makeDetectionJson(radio: 'WiFi', label: 'MySSID'),
        gps,
        now,
      );
      expect(wifi.ssid, 'MySSID');
      expect(wifi.bleName, isNull);

      final ble = RfDetection.fromSerialJson(
        makeDetectionJson(radio: 'BLE', label: 'MyBLE'),
        gps,
        now,
      );
      expect(ble.bleName, 'MyBLE');
      expect(ble.ssid, isNull);
    });

    test('defaults label to MAC when label missing', () {
      final json = makeDetectionJson();
      (json['target'] as Map).remove('label');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.label, d.mac);
    });

    test('defaults category to unknown when missing', () {
      final json = makeDetectionJson();
      (json['target'] as Map).remove('category');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.category, 'unknown');
    });

    test('defaults alertLevel to 0 when missing', () {
      final json = makeDetectionJson();
      (json['target'] as Map).remove('alert_level');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.alertLevel, 0);
    });

    test('defaults certainty to 0 when missing', () {
      final json = makeDetectionJson();
      (json['target'] as Map).remove('certainty');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.maxCertainty, 0);
    });

    test('handles empty detectors map', () {
      final json = makeDetectionJson(detectors: {});
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.detectorData, isEmpty);
      expect(d.matchFlags, 0);
    });

    test('handles missing detectors key', () {
      final json = makeDetectionJson();
      (json['target'] as Map).remove('detectors');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.detectorData, isEmpty);
      expect(d.matchFlags, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // RfDetection.fromSerialJson — flock-you format
  // ---------------------------------------------------------------------------
  group('RfDetection.fromSerialJson (flock-you format)', () {
    final gps = LatLng(45.0, -93.0);
    final now = DateTime(2025, 6, 1, 12, 0, 0);

    test('parses mac_prefix detection', () {
      final json = makeFlockyouDetectionJson();
      final d = RfDetection.fromSerialJson(json, gps, now);

      expect(d.mac, '58:8e:81:fd:9b:ca');
      expect(d.oui, '58:8e:81');
      expect(d.label, 'FS Ext Battery');
      expect(d.radioType, 'BLE');
      expect(d.alertLevel, 2);
      expect(d.maxCertainty, 20);
      expect(d.category, 'unknown');
      expect(d.bleName, 'FS Ext Battery');
      expect(d.firstSeenAt, now);
      expect(d.lastSeenAt, now);
      expect(d.sightingCount, 1);
      expect(d.bestPosition, gps);
    });

    test('parses ble_name detection', () {
      final json = makeFlockyouDetectionJson(
        detectionMethod: 'ble_name',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'Flock Camera',
      );
      final d = RfDetection.fromSerialJson(json, gps, now);

      expect(d.mac, 'aa:bb:cc:dd:ee:ff');
      expect(d.label, 'Flock Camera');
      expect(d.maxCertainty, 55);
      expect(d.alertLevel, 2);
    });

    test('parses ble_mfr_id detection', () {
      final json = makeFlockyouDetectionJson(detectionMethod: 'ble_mfr_id');
      final d = RfDetection.fromSerialJson(json, gps, now);

      expect(d.maxCertainty, 45);
      expect(d.alertLevel, 2);
    });

    test('parses raven_uuid detection', () {
      final json = makeFlockyouDetectionJson(
        detectionMethod: 'raven_uuid',
        isRaven: true,
        ravenFw: '1.3.x',
        deviceName: 'Raven-ABC',
      );
      final d = RfDetection.fromSerialJson(json, gps, now);

      expect(d.category, 'acoustic_detector');
      expect(d.maxCertainty, 80);
      expect(d.alertLevel, 3);
      expect(d.detectorData.containsKey('raven_fw'), isTrue);
    });

    test('lowercases MAC address', () {
      final json = makeFlockyouDetectionJson(macAddress: 'AA:BB:CC:DD:EE:FF');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.mac, 'aa:bb:cc:dd:ee:ff');
    });

    test('maps bluetooth_le protocol to BLE', () {
      final json = makeFlockyouDetectionJson(protocol: 'bluetooth_le');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.radioType, 'BLE');
    });

    test('defaults label to MAC when device_name missing', () {
      final json = makeFlockyouDetectionJson();
      json.remove('device_name');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.label, d.mac);
    });

    test('matchFlags set for mac_prefix', () {
      final json = makeFlockyouDetectionJson(detectionMethod: 'mac_prefix');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.matchFlags, 1 << 7); // flock_oui bit
    });

    test('matchFlags set for raven_uuid', () {
      final json = makeFlockyouDetectionJson(detectionMethod: 'raven_uuid');
      final d = RfDetection.fromSerialJson(json, gps, now);
      expect(d.matchFlags, 1 << 4); // raven_custom_uuid bit
    });
  });

  // ---------------------------------------------------------------------------
  // RfSighting.fromSerialJson — flock-you format
  // ---------------------------------------------------------------------------
  group('RfSighting.fromSerialJson (flock-you format)', () {
    final gps = LatLng(45.0, -93.0);
    final now = DateTime(2025, 6, 1, 12, 0, 0);

    test('parses all fields', () {
      final json = makeFlockyouDetectionJson(rssi: -72);
      final s = RfSighting.fromSerialJson(json, gps, 5.0, now);

      expect(s.mac, '58:8e:81:fd:9b:ca');
      expect(s.coord, gps);
      expect(s.gpsAccuracy, 5.0);
      expect(s.rssi, -72);
      expect(s.channel, isNull);
      expect(s.seenAt, now);
      expect(s.rawJson, isNotNull);
    });

    test('lowercases MAC', () {
      final json = makeFlockyouDetectionJson(macAddress: 'AA:BB:CC:DD:EE:FF');
      final s = RfSighting.fromSerialJson(json, gps, null, now);
      expect(s.mac, 'aa:bb:cc:dd:ee:ff');
    });
  });

  // ---------------------------------------------------------------------------
  // _detectorNameToBit (via fromSerialJson matchFlags)
  // ---------------------------------------------------------------------------
  group('matchFlags bit mapping', () {
    final gps = LatLng(0, 0);
    final now = DateTime(2025, 6, 1);

    test('ssid_format maps to bit 0', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'ssid_format': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 0);
    });

    test('ssid_keyword maps to bit 1', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'ssid_keyword': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 1);
    });

    test('mac_oui maps to bit 2', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'mac_oui': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 2);
    });

    test('ble_name maps to bit 3', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'ble_name': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 3);
    });

    test('raven_custom_uuid maps to bit 4', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'raven_custom_uuid': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 4);
    });

    test('raven_std_uuid maps to bit 5', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'raven_std_uuid': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 5);
    });

    test('rssi_modifier maps to bit 6', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'rssi_modifier': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 6);
    });

    test('flock_oui maps to bit 7', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'flock_oui': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 7);
    });

    test('surveillance_oui maps to bit 8', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'surveillance_oui': 50}),
        gps,
        now,
      );
      expect(d.matchFlags, 1 << 8);
    });

    test('all 9 detectors produce 0x1FF', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {
          'ssid_format': 10,
          'ssid_keyword': 20,
          'mac_oui': 30,
          'ble_name': 40,
          'raven_custom_uuid': 50,
          'raven_std_uuid': 60,
          'rssi_modifier': 70,
          'flock_oui': 80,
          'surveillance_oui': 90,
        }),
        gps,
        now,
      );
      expect(d.matchFlags, 0x1FF);
    });

    test('unknown detector names are ignored in flags', () {
      final d = RfDetection.fromSerialJson(
        makeDetectionJson(detectors: {'unknown_detector': 50, 'flock_oui': 80}),
        gps,
        now,
      );
      // flock_oui bit set, unknown ignored
      expect(d.matchFlags, 1 << 7);
      // but unknown still in detectorData map
      expect(d.detectorData['unknown_detector'], 50);
    });
  });

  // ---------------------------------------------------------------------------
  // RfDetection.toDbRow
  // ---------------------------------------------------------------------------
  group('RfDetection.toDbRow', () {
    test('serializes all fields', () {
      final d = RfDetection(
        mac: 'aa:bb:cc:dd:ee:ff',
        oui: 'aa:bb:cc',
        label: 'TestDevice',
        radioType: 'WiFi',
        category: 'flock_safety_camera',
        alertLevel: 3,
        maxCertainty: 90,
        matchFlags: 0x83,
        detectorData: {'ssid_format': 75, 'flock_oui': 90},
        ssid: 'TestSSID',
        bleName: null,
        bleServiceUuids: null,
        osmNodeId: 12345,
        firstSeenAt: DateTime(2025, 1, 1),
        lastSeenAt: DateTime(2025, 6, 1),
        sightingCount: 5,
        notes: 'test note',
      );

      final row = d.toDbRow();
      expect(row['mac'], 'aa:bb:cc:dd:ee:ff');
      expect(row['oui'], 'aa:bb:cc');
      expect(row['label'], 'TestDevice');
      expect(row['radio_type'], 'WiFi');
      expect(row['category'], 'flock_safety_camera');
      expect(row['alert_level'], 3);
      expect(row['max_certainty'], 90);
      expect(row['match_flags'], 0x83);
      expect(row['ssid'], 'TestSSID');
      expect(row['ble_name'], isNull);
      expect(row['ble_service_uuids'], isNull);
      expect(row['osm_node_id'], 12345);
      expect(row['sighting_count'], 5);
      expect(row['notes'], 'test note');
    });

    test('detectorData serialized as JSON string', () {
      final d = RfDetection(
        mac: 'aa:bb:cc:dd:ee:ff',
        oui: 'aa:bb:cc',
        label: 'X',
        radioType: 'WiFi',
        category: 'unknown',
        alertLevel: 0,
        maxCertainty: 0,
        matchFlags: 0,
        detectorData: {'a': 1, 'b': 2},
        firstSeenAt: DateTime(2025, 1, 1),
        lastSeenAt: DateTime(2025, 1, 1),
      );
      final row = d.toDbRow();
      final decoded = jsonDecode(row['detector_data'] as String);
      expect(decoded, {'a': 1, 'b': 2});
    });

    test('timestamps serialized as ISO 8601', () {
      final dt = DateTime(2025, 6, 15, 14, 30, 0);
      final d = RfDetection(
        mac: 'aa:bb:cc:dd:ee:ff',
        oui: 'aa:bb:cc',
        label: 'X',
        radioType: 'WiFi',
        category: 'unknown',
        alertLevel: 0,
        maxCertainty: 0,
        matchFlags: 0,
        detectorData: {},
        firstSeenAt: dt,
        lastSeenAt: dt,
      );
      final row = d.toDbRow();
      expect(row['first_seen_at'], dt.toIso8601String());
      expect(row['last_seen_at'], dt.toIso8601String());
    });
  });

  // ---------------------------------------------------------------------------
  // RfDetection.fromDbRow
  // ---------------------------------------------------------------------------
  group('RfDetection.fromDbRow', () {
    test('parses all fields', () {
      final row = {
        'mac': 'aa:bb:cc:dd:ee:ff',
        'oui': 'aa:bb:cc',
        'label': 'TestDevice',
        'radio_type': 'WiFi',
        'category': 'flock_safety_camera',
        'alert_level': 3,
        'max_certainty': 90,
        'match_flags': 131,
        'detector_data': '{"ssid_format":75,"flock_oui":90}',
        'ssid': 'TestSSID',
        'ble_name': null,
        'ble_service_uuids': null,
        'osm_node_id': 12345,
        'first_seen_at': '2025-01-01T00:00:00.000',
        'last_seen_at': '2025-06-01T00:00:00.000',
        'sighting_count': 5,
        'notes': 'a note',
        'latest_lat': null,
        'latest_lng': null,
      };

      final d = RfDetection.fromDbRow(row);
      expect(d.mac, 'aa:bb:cc:dd:ee:ff');
      expect(d.oui, 'aa:bb:cc');
      expect(d.label, 'TestDevice');
      expect(d.radioType, 'WiFi');
      expect(d.alertLevel, 3);
      expect(d.maxCertainty, 90);
      expect(d.matchFlags, 131);
      expect(d.detectorData, {'ssid_format': 75, 'flock_oui': 90});
      expect(d.ssid, 'TestSSID');
      expect(d.osmNodeId, 12345);
      expect(d.sightingCount, 5);
      expect(d.notes, 'a note');
      expect(d.bestPosition, isNull);
    });

    test('handles null detector_data', () {
      final row = _minimalDbRow();
      row['detector_data'] = null;
      final d = RfDetection.fromDbRow(row);
      expect(d.detectorData, isEmpty);
    });

    test('handles empty detector_data string', () {
      final row = _minimalDbRow();
      row['detector_data'] = '';
      final d = RfDetection.fromDbRow(row);
      expect(d.detectorData, isEmpty);
    });

    test('reconstructs bestPosition from latest_lat/latest_lng', () {
      final row = _minimalDbRow();
      row['latest_lat'] = 45.0;
      row['latest_lng'] = -93.0;
      final d = RfDetection.fromDbRow(row);
      expect(d.bestPosition, isNotNull);
      expect(d.bestPosition!.latitude, 45.0);
      expect(d.bestPosition!.longitude, -93.0);
    });

    test('defaults sightingCount to 1 when null', () {
      final row = _minimalDbRow();
      row['sighting_count'] = null;
      final d = RfDetection.fromDbRow(row);
      expect(d.sightingCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // RfDetection round-trip
  // ---------------------------------------------------------------------------
  group('RfDetection round-trip (toDbRow -> fromDbRow)', () {
    test('WiFi detection survives round-trip', () {
      final gps = LatLng(45.0, -93.0);
      final now = DateTime(2025, 6, 1, 12, 0, 0);
      final original = RfDetection.fromSerialJson(
        makeDetectionJson(),
        gps,
        now,
      );

      final row = original.toDbRow();
      // Simulate DB: add lat/lng join columns
      row['latest_lat'] = null;
      row['latest_lng'] = null;
      final restored = RfDetection.fromDbRow(row);

      expect(restored.mac, original.mac);
      expect(restored.oui, original.oui);
      expect(restored.label, original.label);
      expect(restored.radioType, original.radioType);
      expect(restored.category, original.category);
      expect(restored.alertLevel, original.alertLevel);
      expect(restored.maxCertainty, original.maxCertainty);
      expect(restored.matchFlags, original.matchFlags);
      expect(restored.detectorData, original.detectorData);
      expect(restored.ssid, original.ssid);
      expect(restored.firstSeenAt, original.firstSeenAt);
      expect(restored.lastSeenAt, original.lastSeenAt);
      expect(restored.sightingCount, original.sightingCount);
    });

    test('BLE detection survives round-trip', () {
      final gps = LatLng(0, 0);
      final now = DateTime.now();
      final original = RfDetection.fromSerialJson(
        makeDetectionJson(radio: 'BLE', label: 'Raven-X', detectors: {'ble_name': 80}),
        gps,
        now,
      );

      final row = original.toDbRow();
      row['latest_lat'] = null;
      row['latest_lng'] = null;
      final restored = RfDetection.fromDbRow(row);

      expect(restored.radioType, 'BLE');
      expect(restored.bleName, 'Raven-X');
      expect(restored.ssid, isNull);
    });

    test('null optional fields survive round-trip', () {
      final d = RfDetection(
        mac: 'aa:bb:cc:dd:ee:ff',
        oui: 'aa:bb:cc',
        label: 'X',
        radioType: 'WiFi',
        category: 'unknown',
        alertLevel: 0,
        maxCertainty: 0,
        matchFlags: 0,
        detectorData: {},
        firstSeenAt: DateTime(2025, 1, 1),
        lastSeenAt: DateTime(2025, 1, 1),
      );

      final row = d.toDbRow();
      row['latest_lat'] = null;
      row['latest_lng'] = null;
      final restored = RfDetection.fromDbRow(row);

      expect(restored.ssid, isNull);
      expect(restored.bleName, isNull);
      expect(restored.bleServiceUuids, isNull);
      expect(restored.osmNodeId, isNull);
      expect(restored.notes, isNull);
      expect(restored.bestPosition, isNull);
    });

    test('populated optional fields survive round-trip', () {
      final d = RfDetection(
        mac: 'aa:bb:cc:dd:ee:ff',
        oui: 'aa:bb:cc',
        label: 'Full',
        radioType: 'WiFi',
        category: 'test',
        alertLevel: 2,
        maxCertainty: 80,
        matchFlags: 3,
        detectorData: {'a': 1},
        ssid: 'MySsid',
        bleName: 'MyBle',
        bleServiceUuids: 'uuid1,uuid2',
        osmNodeId: 999,
        firstSeenAt: DateTime(2025, 1, 1),
        lastSeenAt: DateTime(2025, 6, 1),
        sightingCount: 10,
        notes: 'note',
      );

      final row = d.toDbRow();
      row['latest_lat'] = 45.0;
      row['latest_lng'] = -93.0;
      final restored = RfDetection.fromDbRow(row);

      expect(restored.ssid, 'MySsid');
      expect(restored.bleName, 'MyBle');
      expect(restored.bleServiceUuids, 'uuid1,uuid2');
      expect(restored.osmNodeId, 999);
      expect(restored.notes, 'note');
      expect(restored.sightingCount, 10);
      expect(restored.bestPosition!.latitude, 45.0);
    });
  });

  // ---------------------------------------------------------------------------
  // RfDetection.isSubmitted
  // ---------------------------------------------------------------------------
  group('RfDetection.isSubmitted', () {
    test('true when osmNodeId is set', () {
      final d = RfDetection(
        mac: 'x',
        oui: 'x',
        label: 'x',
        radioType: 'WiFi',
        category: 'x',
        alertLevel: 0,
        maxCertainty: 0,
        matchFlags: 0,
        detectorData: {},
        firstSeenAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
        osmNodeId: 123,
      );
      expect(d.isSubmitted, isTrue);
    });

    test('false when osmNodeId is null', () {
      final d = RfDetection(
        mac: 'x',
        oui: 'x',
        label: 'x',
        radioType: 'WiFi',
        category: 'x',
        alertLevel: 0,
        maxCertainty: 0,
        matchFlags: 0,
        detectorData: {},
        firstSeenAt: DateTime.now(),
        lastSeenAt: DateTime.now(),
      );
      expect(d.isSubmitted, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // RfSighting.fromSerialJson
  // ---------------------------------------------------------------------------
  group('RfSighting.fromSerialJson', () {
    final gps = LatLng(45.0, -93.0);
    final now = DateTime(2025, 6, 1, 12, 0, 0);

    test('parses all fields', () {
      final json = makeDetectionJson(rssi: -55, channel: 11);
      final s = RfSighting.fromSerialJson(json, gps, 5.0, now);

      expect(s.mac, 'b4:1e:52:aa:bb:cc');
      expect(s.coord, gps);
      expect(s.gpsAccuracy, 5.0);
      expect(s.rssi, -55);
      expect(s.channel, 11);
      expect(s.seenAt, now);
      expect(s.rawJson, isNotNull);
    });

    test('lowercases MAC', () {
      final json = makeDetectionJson(mac: 'AA:BB:CC:DD:EE:FF');
      final s = RfSighting.fromSerialJson(json, gps, null, now);
      expect(s.mac, 'aa:bb:cc:dd:ee:ff');
    });

    test('handles null channel', () {
      final json = makeDetectionJson();
      // Rebuild source map with null channel to avoid type issues
      final source = Map<String, dynamic>.from(json['source'] as Map);
      source['channel'] = null;
      json['source'] = source;
      final s = RfSighting.fromSerialJson(json, gps, null, now);
      expect(s.channel, isNull);
    });

    test('rawJson encodes original JSON', () {
      final json = makeDetectionJson();
      final s = RfSighting.fromSerialJson(json, gps, null, now);
      final decoded = jsonDecode(s.rawJson!);
      expect(decoded['event'], 'target_detected');
    });
  });

  // ---------------------------------------------------------------------------
  // RfSighting.toDbRow / fromDbRow
  // ---------------------------------------------------------------------------
  group('RfSighting.toDbRow', () {
    test('serializes all fields', () {
      final s = RfSighting(
        mac: 'aa:bb:cc:dd:ee:ff',
        coord: LatLng(45.0, -93.0),
        gpsAccuracy: 5.0,
        rssi: -60,
        channel: 6,
        seenAt: DateTime(2025, 6, 1),
        rawJson: '{"test":true}',
      );

      final row = s.toDbRow();
      expect(row['mac'], 'aa:bb:cc:dd:ee:ff');
      expect(row['lat'], 45.0);
      expect(row['lng'], -93.0);
      expect(row['gps_accuracy'], 5.0);
      expect(row['rssi'], -60);
      expect(row['channel'], 6);
      expect(row['seen_at'], '2025-06-01T00:00:00.000');
      expect(row['raw_json'], '{"test":true}');
    });
  });

  group('RfSighting.fromDbRow', () {
    test('parses all fields', () {
      final row = {
        'id': 42,
        'mac': 'aa:bb:cc:dd:ee:ff',
        'lat': 45.0,
        'lng': -93.0,
        'gps_accuracy': 5.0,
        'rssi': -60,
        'channel': 6,
        'seen_at': '2025-06-01T00:00:00.000',
        'raw_json': '{"test":true}',
      };

      final s = RfSighting.fromDbRow(row);
      expect(s.id, 42);
      expect(s.mac, 'aa:bb:cc:dd:ee:ff');
      expect(s.coord.latitude, 45.0);
      expect(s.coord.longitude, -93.0);
      expect(s.gpsAccuracy, 5.0);
      expect(s.rssi, -60);
      expect(s.channel, 6);
      expect(s.rawJson, '{"test":true}');
    });

    test('handles null optional fields', () {
      final row = {
        'id': null,
        'mac': 'aa:bb:cc:dd:ee:ff',
        'lat': 45.0,
        'lng': -93.0,
        'gps_accuracy': null,
        'rssi': -60,
        'channel': null,
        'seen_at': '2025-06-01T00:00:00.000',
        'raw_json': null,
      };

      final s = RfSighting.fromDbRow(row);
      expect(s.id, isNull);
      expect(s.gpsAccuracy, isNull);
      expect(s.channel, isNull);
      expect(s.rawJson, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // RfSighting round-trip
  // ---------------------------------------------------------------------------
  group('RfSighting round-trip (toDbRow -> fromDbRow)', () {
    test('all fields survive', () {
      final original = RfSighting(
        mac: 'aa:bb:cc:dd:ee:ff',
        coord: LatLng(45.5, -93.25),
        gpsAccuracy: 3.5,
        rssi: -72,
        channel: 11,
        seenAt: DateTime(2025, 6, 15, 10, 30),
        rawJson: '{"x":1}',
      );

      final row = original.toDbRow();
      // Simulate DB auto-increment id
      row['id'] = 1;
      final restored = RfSighting.fromDbRow(row);

      expect(restored.mac, original.mac);
      expect(restored.coord.latitude, original.coord.latitude);
      expect(restored.coord.longitude, original.coord.longitude);
      expect(restored.gpsAccuracy, original.gpsAccuracy);
      expect(restored.rssi, original.rssi);
      expect(restored.channel, original.channel);
      expect(restored.seenAt, original.seenAt);
      expect(restored.rawJson, original.rawJson);
    });

    test('null optional fields survive', () {
      final original = RfSighting(
        mac: 'aa:bb:cc:dd:ee:ff',
        coord: LatLng(0, 0),
        rssi: -80,
        seenAt: DateTime(2025, 1, 1),
      );

      final row = original.toDbRow();
      row['id'] = null;
      final restored = RfSighting.fromDbRow(row);

      expect(restored.gpsAccuracy, isNull);
      expect(restored.channel, isNull);
      expect(restored.rawJson, isNull);
    });
  });
}

/// Minimal valid DB row for RfDetection (used as base for override tests).
Map<String, dynamic> _minimalDbRow() => {
      'mac': 'aa:bb:cc:dd:ee:ff',
      'oui': 'aa:bb:cc',
      'label': 'X',
      'radio_type': 'WiFi',
      'category': 'unknown',
      'alert_level': 0,
      'max_certainty': 0,
      'match_flags': 0,
      'detector_data': '{}',
      'ssid': null,
      'ble_name': null,
      'ble_service_uuids': null,
      'osm_node_id': null,
      'first_seen_at': '2025-01-01T00:00:00.000',
      'last_seen_at': '2025-01-01T00:00:00.000',
      'sighting_count': 1,
      'notes': null,
      'latest_lat': null,
      'latest_lng': null,
    };

import 'dart:convert';
import 'package:latlong2/latlong.dart';

/// A unique RF device identified by MAC address, with aggregated detection data.
/// Maps to the `rf_devices` SQLite table.
class RfDetection {
  final String mac;
  final String oui;
  String label;
  final String radioType; // "WiFi" or "BLE"
  String category;
  int alertLevel;
  int maxCertainty;
  int matchFlags;
  Map<String, int> detectorData;
  String? ssid;
  String? bleName;
  String? bleServiceUuids;
  int? osmNodeId;
  DateTime firstSeenAt;
  DateTime lastSeenAt;
  int sightingCount;
  String? notes;

  /// Best known position (from most recent sighting, joined at query time).
  LatLng? bestPosition;

  RfDetection({
    required this.mac,
    required this.oui,
    required this.label,
    required this.radioType,
    required this.category,
    required this.alertLevel,
    required this.maxCertainty,
    required this.matchFlags,
    required this.detectorData,
    this.ssid,
    this.bleName,
    this.bleServiceUuids,
    this.osmNodeId,
    required this.firstSeenAt,
    required this.lastSeenAt,
    this.sightingCount = 1,
    this.notes,
    this.bestPosition,
  });

  /// Parse from FlockSquawk serial JSON + phone GPS position.
  ///
  /// Expected JSON shape (from TelemetryReporter.h):
  /// ```json
  /// {
  ///   "event": "target_detected",
  ///   "source": { "radio": "WiFi"|"BLE", "channel": 6, "rssi": -45 },
  ///   "target": {
  ///     "mac": "b4:1e:52:aa:bb:cc",
  ///     "label": "Flock-a1b2c3",
  ///     "certainty": 90,
  ///     "alert_level": 3,
  ///     "category": "flock_safety_camera",
  ///     "detectors": { "ssid_format": 75, "flock_oui": 90 }
  ///   }
  /// }
  /// ```
  factory RfDetection.fromSerialJson(
    Map<String, dynamic> json,
    LatLng gpsPos,
    DateTime now,
  ) {
    final target = json['target'] as Map<String, dynamic>;
    final source = json['source'] as Map<String, dynamic>;
    final mac = (target['mac'] as String).toLowerCase();
    final oui = mac.substring(0, 8); // "b4:1e:52"
    final radioType = source['radio'] as String;

    // Extract detector data
    final detectorsRaw = target['detectors'] as Map<String, dynamic>? ?? {};
    final detectorData = detectorsRaw.map(
      (k, v) => MapEntry(k, (v as num).toInt()),
    );

    // Compute matchFlags from detector keys
    int matchFlags = 0;
    for (final key in detectorsRaw.keys) {
      final bit = _detectorNameToBit(key);
      if (bit >= 0) matchFlags |= (1 << bit);
    }

    final label = target['label'] as String? ?? mac;

    return RfDetection(
      mac: mac,
      oui: oui,
      label: label,
      radioType: radioType,
      category: target['category'] as String? ?? 'unknown',
      alertLevel: (target['alert_level'] as num?)?.toInt() ?? 0,
      maxCertainty: (target['certainty'] as num?)?.toInt() ?? 0,
      matchFlags: matchFlags,
      detectorData: detectorData,
      ssid: radioType == 'WiFi' ? label : null,
      bleName: radioType == 'BLE' ? label : null,
      firstSeenAt: now,
      lastSeenAt: now,
      sightingCount: 1,
      bestPosition: gpsPos,
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'mac': mac,
      'oui': oui,
      'label': label,
      'radio_type': radioType,
      'category': category,
      'alert_level': alertLevel,
      'max_certainty': maxCertainty,
      'match_flags': matchFlags,
      'detector_data': jsonEncode(detectorData),
      'ssid': ssid,
      'ble_name': bleName,
      'ble_service_uuids': bleServiceUuids,
      'osm_node_id': osmNodeId,
      'first_seen_at': firstSeenAt.toIso8601String(),
      'last_seen_at': lastSeenAt.toIso8601String(),
      'sighting_count': sightingCount,
      'notes': notes,
    };
  }

  factory RfDetection.fromDbRow(Map<String, dynamic> row) {
    Map<String, int> detectorData = {};
    final detectorDataStr = row['detector_data'] as String?;
    if (detectorDataStr != null && detectorDataStr.isNotEmpty) {
      final decoded = jsonDecode(detectorDataStr) as Map<String, dynamic>;
      detectorData = decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
    }

    return RfDetection(
      mac: row['mac'] as String,
      oui: row['oui'] as String,
      label: row['label'] as String,
      radioType: row['radio_type'] as String,
      category: row['category'] as String,
      alertLevel: row['alert_level'] as int,
      maxCertainty: row['max_certainty'] as int,
      matchFlags: row['match_flags'] as int,
      detectorData: detectorData,
      ssid: row['ssid'] as String?,
      bleName: row['ble_name'] as String?,
      bleServiceUuids: row['ble_service_uuids'] as String?,
      osmNodeId: row['osm_node_id'] as int?,
      firstSeenAt: DateTime.parse(row['first_seen_at'] as String),
      lastSeenAt: DateTime.parse(row['last_seen_at'] as String),
      sightingCount: row['sighting_count'] as int? ?? 1,
      notes: row['notes'] as String?,
      // bestPosition joined at query time via latest sighting
      bestPosition: row['latest_lat'] != null && row['latest_lng'] != null
          ? LatLng(
              (row['latest_lat'] as num).toDouble(),
              (row['latest_lng'] as num).toDouble(),
            )
          : null,
    );
  }

  bool get isSubmitted => osmNodeId != null;

  /// Map detector name strings (from JSON) to bit positions matching DetectorFlag enum.
  static int _detectorNameToBit(String name) {
    const mapping = {
      'ssid_format': 0,
      'ssid_keyword': 1,
      'mac_oui': 2,
      'ble_name': 3,
      'raven_custom_uuid': 4,
      'raven_std_uuid': 5,
      'rssi_modifier': 6,
      'flock_oui': 7,
      'surveillance_oui': 8,
    };
    return mapping[name] ?? -1;
  }
}

/// A single GPS-stamped sighting of an RF device.
/// Maps to the `rf_sightings` SQLite table.
class RfSighting {
  final int? id;
  final String mac;
  final LatLng coord;
  final double? gpsAccuracy;
  final int rssi;
  final int? channel;
  final DateTime seenAt;
  final String? rawJson;

  RfSighting({
    this.id,
    required this.mac,
    required this.coord,
    this.gpsAccuracy,
    required this.rssi,
    this.channel,
    required this.seenAt,
    this.rawJson,
  });

  factory RfSighting.fromSerialJson(
    Map<String, dynamic> json,
    LatLng gpsPos,
    double? gpsAccuracy,
    DateTime now,
  ) {
    final target = json['target'] as Map<String, dynamic>;
    final source = json['source'] as Map<String, dynamic>;
    final mac = (target['mac'] as String).toLowerCase();

    return RfSighting(
      mac: mac,
      coord: gpsPos,
      gpsAccuracy: gpsAccuracy,
      rssi: (source['rssi'] as num).toInt(),
      channel: (source['channel'] as num?)?.toInt(),
      seenAt: now,
      rawJson: jsonEncode(json),
    );
  }

  Map<String, dynamic> toDbRow() {
    return {
      'mac': mac,
      'lat': coord.latitude,
      'lng': coord.longitude,
      'gps_accuracy': gpsAccuracy,
      'rssi': rssi,
      'channel': channel,
      'seen_at': seenAt.toIso8601String(),
      'raw_json': rawJson,
    };
  }

  factory RfSighting.fromDbRow(Map<String, dynamic> row) {
    return RfSighting(
      id: row['id'] as int?,
      mac: row['mac'] as String,
      coord: LatLng(
        (row['lat'] as num).toDouble(),
        (row['lng'] as num).toDouble(),
      ),
      gpsAccuracy: (row['gps_accuracy'] as num?)?.toDouble(),
      rssi: row['rssi'] as int,
      channel: row['channel'] as int?,
      seenAt: DateTime.parse(row['seen_at'] as String),
      rawJson: row['raw_json'] as String?,
    );
  }
}

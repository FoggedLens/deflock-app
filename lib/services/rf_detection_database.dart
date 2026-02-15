import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

import '../models/rf_detection.dart';

/// SQLite database for RF detection data (devices + sightings).
/// Singleton, following SuspectedLocationDatabase pattern.
class RfDetectionDatabase {
  static final RfDetectionDatabase _instance = RfDetectionDatabase._();
  factory RfDetectionDatabase() => _instance;
  RfDetectionDatabase._();

  Database? _database;
  static const String _dbName = 'rf_detections.db';
  static const int _dbVersion = 1;

  Future<void> init() async {
    if (_database != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final fullPath = path.join(dbPath, _dbName);

      debugPrint('[RfDetectionDatabase] Initializing database at $fullPath');

      _database = await openDatabase(
        fullPath,
        version: _dbVersion,
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
      );

      debugPrint('[RfDetectionDatabase] Database initialized successfully');
    } catch (e) {
      debugPrint('[RfDetectionDatabase] Error initializing database: $e');
      rethrow;
    }
  }

  Future<Database> get database async {
    if (_database == null) {
      await init();
    }
    return _database!;
  }

  Future<void> _createTables(Database db, int version) async {
    debugPrint('[RfDetectionDatabase] Creating tables...');

    await db.execute('''
      CREATE TABLE rf_devices (
        mac               TEXT PRIMARY KEY,
        oui               TEXT NOT NULL,
        label             TEXT NOT NULL,
        radio_type        TEXT NOT NULL,
        category          TEXT NOT NULL,
        alert_level       INTEGER NOT NULL,
        max_certainty     INTEGER NOT NULL,
        match_flags       INTEGER NOT NULL,
        detector_data     TEXT,
        ssid              TEXT,
        ble_name          TEXT,
        ble_service_uuids TEXT,
        osm_node_id       INTEGER,
        first_seen_at     TEXT NOT NULL,
        last_seen_at      TEXT NOT NULL,
        sighting_count    INTEGER DEFAULT 1,
        notes             TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_rf_devices_oui ON rf_devices(oui)');
    await db.execute('CREATE INDEX idx_rf_devices_alert ON rf_devices(alert_level)');
    await db.execute('CREATE INDEX idx_rf_devices_osm ON rf_devices(osm_node_id)');

    await db.execute('''
      CREATE TABLE rf_sightings (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        mac         TEXT NOT NULL REFERENCES rf_devices(mac),
        lat         REAL NOT NULL,
        lng         REAL NOT NULL,
        gps_accuracy REAL,
        rssi        INTEGER NOT NULL,
        channel     INTEGER,
        seen_at     TEXT NOT NULL,
        raw_json    TEXT
      )
    ''');

    await db.execute('CREATE INDEX idx_sightings_mac ON rf_sightings(mac)');
    await db.execute('CREATE INDEX idx_sightings_lat_lng ON rf_sightings(lat, lng)');
    await db.execute('CREATE INDEX idx_sightings_seen ON rf_sightings(seen_at)');

    await db.execute('''
      CREATE TABLE metadata (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Initialize schema version
    await db.insert('metadata', {'key': 'schema_version', 'value': '1'});

    debugPrint('[RfDetectionDatabase] Tables created successfully');
  }

  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    debugPrint('[RfDetectionDatabase] Upgrading from v$oldVersion to v$newVersion');
  }

  /// Insert or update a detection. Escalates alert_level and max_certainty,
  /// merges detector data, updates last_seen and sighting_count.
  Future<void> upsertDetection(RfDetection detection) async {
    final db = await database;

    await db.transaction((txn) async {
      final existing = await txn.query(
        'rf_devices',
        where: 'mac = ?',
        whereArgs: [detection.mac],
      );

      if (existing.isEmpty) {
        await txn.insert('rf_devices', detection.toDbRow());
      } else {
        final old = RfDetection.fromDbRow(existing.first);

        // Escalate: keep highest alert level and certainty
        final newAlertLevel = detection.alertLevel > old.alertLevel
            ? detection.alertLevel
            : old.alertLevel;
        final newCertainty = detection.maxCertainty > old.maxCertainty
            ? detection.maxCertainty
            : old.maxCertainty;

        // Merge match flags (union of all detectors ever seen)
        final newFlags = old.matchFlags | detection.matchFlags;

        // Merge detector data (keep highest weight per detector)
        final mergedDetectors = Map<String, int>.from(old.detectorData);
        for (final entry in detection.detectorData.entries) {
          final existing = mergedDetectors[entry.key];
          if (existing == null || entry.value > existing) {
            mergedDetectors[entry.key] = entry.value;
          }
        }

        // Update label if the new one is more specific (non-MAC)
        final newLabel = (detection.label != detection.mac && old.label == old.mac)
            ? detection.label
            : old.label;

        await txn.update(
          'rf_devices',
          {
            'label': newLabel,
            'alert_level': newAlertLevel,
            'max_certainty': newCertainty,
            'match_flags': newFlags,
            'detector_data': jsonEncode(mergedDetectors),
            'last_seen_at': detection.lastSeenAt.toIso8601String(),
            'sighting_count': old.sightingCount + 1,
            // Merge optional fields if newly available
            if (detection.ssid != null) 'ssid': detection.ssid,
            if (detection.bleName != null) 'ble_name': detection.bleName,
            if (detection.bleServiceUuids != null)
              'ble_service_uuids': detection.bleServiceUuids,
          },
          where: 'mac = ?',
          whereArgs: [detection.mac],
        );
      }
    });
  }

  /// Record a GPS-stamped sighting.
  Future<void> addSighting(RfSighting sighting) async {
    final db = await database;
    await db.insert('rf_sightings', sighting.toDbRow());
  }

  /// Get detections with optional filters, joined with latest sighting position.
  Future<List<RfDetection>> getDetections({
    int? minAlertLevel,
    bool? hasOsmNode,
    int? limit,
  }) async {
    final db = await database;

    final where = <String>[];
    final whereArgs = <dynamic>[];

    if (minAlertLevel != null) {
      where.add('d.alert_level >= ?');
      whereArgs.add(minAlertLevel);
    }
    if (hasOsmNode == true) {
      where.add('d.osm_node_id IS NOT NULL');
    } else if (hasOsmNode == false) {
      where.add('d.osm_node_id IS NULL');
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final results = await db.rawQuery('''
      SELECT d.*, s.lat AS latest_lat, s.lng AS latest_lng
      FROM rf_devices d
      LEFT JOIN (
        SELECT mac, lat, lng
        FROM rf_sightings
        WHERE id IN (SELECT MAX(id) FROM rf_sightings GROUP BY mac)
      ) s ON d.mac = s.mac
      $whereClause
      ORDER BY d.last_seen_at DESC
      ${limit != null ? 'LIMIT $limit' : ''}
    ''', whereArgs);

    return results.map((row) => RfDetection.fromDbRow(row)).toList();
  }

  /// Get detections within map bounds (for marker rendering).
  Future<List<RfDetection>> getDetectionsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT d.*, s.lat AS latest_lat, s.lng AS latest_lng
      FROM rf_devices d
      INNER JOIN (
        SELECT mac, lat, lng
        FROM rf_sightings
        WHERE id IN (SELECT MAX(id) FROM rf_sightings GROUP BY mac)
      ) s ON d.mac = s.mac
      WHERE s.lat BETWEEN ? AND ?
        AND s.lng BETWEEN ? AND ?
      ORDER BY d.alert_level DESC
    ''', [south, north, west, east]);

    return results.map((row) => RfDetection.fromDbRow(row)).toList();
  }

  /// Get all sightings for a specific device MAC.
  Future<List<RfSighting>> getSightingsForMac(String mac) async {
    final db = await database;
    final results = await db.query(
      'rf_sightings',
      where: 'mac = ?',
      whereArgs: [mac],
      orderBy: 'seen_at DESC',
    );
    return results.map((row) => RfSighting.fromDbRow(row)).toList();
  }

  /// Link a detection to a submitted OSM node.
  Future<void> linkToOsmNode(String mac, int osmNodeId) async {
    final db = await database;
    await db.update(
      'rf_devices',
      {'osm_node_id': osmNodeId},
      where: 'mac = ?',
      whereArgs: [mac],
    );
  }

  /// Get detections not yet submitted to OSM.
  Future<List<RfDetection>> getUnsubmittedDetections() async {
    return getDetections(hasOsmNode: false);
  }

  /// Delete a detection and all its sightings.
  Future<void> deleteDetection(String mac) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('rf_sightings', where: 'mac = ?', whereArgs: [mac]);
      await txn.delete('rf_devices', where: 'mac = ?', whereArgs: [mac]);
    });
  }

  /// Get aggregate stats.
  Future<Map<String, dynamic>> getStats() async {
    final db = await database;

    final totalResult = await db.rawQuery('SELECT COUNT(*) as c FROM rf_devices');
    final total = Sqflite.firstIntValue(totalResult) ?? 0;

    final submittedResult = await db.rawQuery(
      'SELECT COUNT(*) as c FROM rf_devices WHERE osm_node_id IS NOT NULL',
    );
    final submitted = Sqflite.firstIntValue(submittedResult) ?? 0;

    final byAlertLevel = <int, int>{};
    final alertResults = await db.rawQuery(
      'SELECT alert_level, COUNT(*) as c FROM rf_devices GROUP BY alert_level',
    );
    for (final row in alertResults) {
      byAlertLevel[row['alert_level'] as int] = row['c'] as int;
    }

    return {
      'total': total,
      'submitted': submitted,
      'unsubmitted': total - submitted,
      'byAlertLevel': byAlertLevel,
    };
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Reset singleton state for testing. Optionally inject a pre-opened database.
  @visibleForTesting
  static void resetForTesting({Database? database}) {
    _instance._database = database;
  }

  /// Expose table creation for tests that supply their own in-memory DB.
  @visibleForTesting
  static Future<void> createTablesForTesting(Database db) async {
    await _instance._createTables(db, _dbVersion);
  }
}

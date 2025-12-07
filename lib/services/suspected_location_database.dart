import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

import '../models/suspected_location.dart';

/// Database service for suspected location data
/// Replaces the SharedPreferences-based cache to handle large datasets efficiently
class SuspectedLocationDatabase {
  static final SuspectedLocationDatabase _instance = SuspectedLocationDatabase._();
  factory SuspectedLocationDatabase() => _instance;
  SuspectedLocationDatabase._();

  Database? _database;
  static const String _dbName = 'suspected_locations.db';
  static const int _dbVersion = 1;

  // Table and column names
  static const String _tableName = 'suspected_locations';
  static const String _columnTicketNo = 'ticket_no';
  static const String _columnCentroidLat = 'centroid_lat';
  static const String _columnCentroidLng = 'centroid_lng';
  static const String _columnBounds = 'bounds';
  static const String _columnGeoJson = 'geo_json';
  static const String _columnAllFields = 'all_fields';

  // Metadata table for tracking last fetch time
  static const String _metaTableName = 'metadata';
  static const String _metaColumnKey = 'key';
  static const String _metaColumnValue = 'value';
  static const String _lastFetchKey = 'last_fetch_time';

  /// Initialize the database
  Future<void> init() async {
    if (_database != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final fullPath = path.join(dbPath, _dbName);

      debugPrint('[SuspectedLocationDatabase] Initializing database at $fullPath');

      _database = await openDatabase(
        fullPath,
        version: _dbVersion,
        onCreate: _createTables,
        onUpgrade: _upgradeTables,
      );

      debugPrint('[SuspectedLocationDatabase] Database initialized successfully');
    } catch (e) {
      debugPrint('[SuspectedLocationDatabase] Error initializing database: $e');
      rethrow;
    }
  }

  /// Create database tables
  Future<void> _createTables(Database db, int version) async {
    debugPrint('[SuspectedLocationDatabase] Creating tables...');

    // Main suspected locations table
    await db.execute('''
      CREATE TABLE $_tableName (
        $_columnTicketNo TEXT PRIMARY KEY,
        $_columnCentroidLat REAL NOT NULL,
        $_columnCentroidLng REAL NOT NULL,
        $_columnBounds TEXT,
        $_columnGeoJson TEXT,
        $_columnAllFields TEXT NOT NULL
      )
    ''');

    // Create spatial index for efficient bounds queries
    await db.execute('''
      CREATE INDEX idx_centroid ON $_tableName ($_columnCentroidLat, $_columnCentroidLng)
    ''');

    // Metadata table for tracking last fetch time and other info
    await db.execute('''
      CREATE TABLE $_metaTableName (
        $_metaColumnKey TEXT PRIMARY KEY,
        $_metaColumnValue TEXT NOT NULL
      )
    ''');

    debugPrint('[SuspectedLocationDatabase] Tables created successfully');
  }

  /// Handle database upgrades
  Future<void> _upgradeTables(Database db, int oldVersion, int newVersion) async {
    debugPrint('[SuspectedLocationDatabase] Upgrading database from version $oldVersion to $newVersion');
    // Future migrations would go here
  }

  /// Get database instance, initializing if needed
  Future<Database> get database async {
    if (_database == null) {
      await init();
    }
    return _database!;
  }

  /// Clear all data and recreate tables
  Future<void> clearAllData() async {
    try {
      final db = await database;
      
      debugPrint('[SuspectedLocationDatabase] Clearing all data...');
      
      // Drop and recreate tables (simpler than DELETE for large datasets)
      await db.execute('DROP TABLE IF EXISTS $_tableName');
      await db.execute('DROP TABLE IF EXISTS $_metaTableName');
      await _createTables(db, _dbVersion);
      
      debugPrint('[SuspectedLocationDatabase] All data cleared successfully');
    } catch (e) {
      debugPrint('[SuspectedLocationDatabase] Error clearing data: $e');
      rethrow;
    }
  }

  /// Insert suspected locations in batch
  Future<void> insertBatch(List<Map<String, dynamic>> rawDataList, DateTime fetchTime) async {
    try {
      final db = await database;
      
      debugPrint('[SuspectedLocationDatabase] Starting batch insert of ${rawDataList.length} entries...');
      
      // Clear existing data first
      await clearAllData();
      
      // Process entries in batches to avoid memory issues
      const batchSize = 1000;
      int totalInserted = 0;
      int validCount = 0;
      int errorCount = 0;
      
      // Start transaction for better performance
      await db.transaction((txn) async {
        for (int i = 0; i < rawDataList.length; i += batchSize) {
          final batch = txn.batch();
          final endIndex = (i + batchSize < rawDataList.length) ? i + batchSize : rawDataList.length;
          final currentBatch = rawDataList.sublist(i, endIndex);
          
          for (final rowData in currentBatch) {
            try {
              // Create temporary SuspectedLocation to extract centroid and bounds
              final tempLocation = SuspectedLocation.fromCsvRow(rowData);
              
              // Skip entries with zero coordinates
              if (tempLocation.centroid.latitude == 0 && tempLocation.centroid.longitude == 0) {
                continue;
              }
              
              // Prepare data for database insertion
              final dbRow = {
                _columnTicketNo: tempLocation.ticketNo,
                _columnCentroidLat: tempLocation.centroid.latitude,
                _columnCentroidLng: tempLocation.centroid.longitude,
                _columnBounds: tempLocation.bounds.isNotEmpty 
                    ? jsonEncode(tempLocation.bounds.map((p) => [p.latitude, p.longitude]).toList())
                    : null,
                _columnGeoJson: tempLocation.geoJson != null ? jsonEncode(tempLocation.geoJson!) : null,
                _columnAllFields: jsonEncode(tempLocation.allFields),
              };
              
              batch.insert(_tableName, dbRow, conflictAlgorithm: ConflictAlgorithm.replace);
              validCount++;
              
            } catch (e) {
              errorCount++;
              // Skip invalid entries
              continue;
            }
          }
          
          // Commit this batch
          await batch.commit(noResult: true);
          totalInserted += currentBatch.length;
          
          // Log progress every few batches
          if ((i ~/ batchSize) % 5 == 0) {
            debugPrint('[SuspectedLocationDatabase] Processed ${i + currentBatch.length}/${rawDataList.length} entries...');
          }
        }
        
        // Insert metadata
        await txn.insert(
          _metaTableName, 
          {
            _metaColumnKey: _lastFetchKey,
            _metaColumnValue: fetchTime.millisecondsSinceEpoch.toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      
      debugPrint('[SuspectedLocationDatabase] Batch insert complete - Valid: $validCount, Errors: $errorCount');
    } catch (e) {
      debugPrint('[SuspectedLocationDatabase] Error in batch insert: $e');
      rethrow;
    }
  }

  /// Get suspected locations within bounding box
  Future<List<SuspectedLocation>> getLocationsInBounds(LatLngBounds bounds) async {
    try {
      final db = await database;
      
      // Query with spatial bounds (simple lat/lng box filtering)
      final result = await db.query(
        _tableName,
        where: '''
          $_columnCentroidLat <= ? AND $_columnCentroidLat >= ? AND 
          $_columnCentroidLng <= ? AND $_columnCentroidLng >= ?
        ''',
        whereArgs: [bounds.north, bounds.south, bounds.east, bounds.west],
      );
      
      // Convert database rows to SuspectedLocation objects
      final locations = <SuspectedLocation>[];
      for (final row in result) {
        try {
          final allFields = Map<String, dynamic>.from(jsonDecode(row[_columnAllFields] as String));
          
          // Reconstruct bounds if available
          List<LatLng> boundsList = [];
          final boundsJson = row[_columnBounds] as String?;
          if (boundsJson != null) {
            final boundsData = jsonDecode(boundsJson) as List;
            boundsList = boundsData.map((b) => LatLng(
              (b[0] as num).toDouble(),
              (b[1] as num).toDouble(),
            )).toList();
          }
          
          // Reconstruct GeoJSON if available
          Map<String, dynamic>? geoJson;
          final geoJsonString = row[_columnGeoJson] as String?;
          if (geoJsonString != null) {
            geoJson = Map<String, dynamic>.from(jsonDecode(geoJsonString));
          }
          
          final location = SuspectedLocation(
            ticketNo: row[_columnTicketNo] as String,
            centroid: LatLng(
              row[_columnCentroidLat] as double,
              row[_columnCentroidLng] as double,
            ),
            bounds: boundsList,
            geoJson: geoJson,
            allFields: allFields,
          );
          
          locations.add(location);
        } catch (e) {
          // Skip invalid database entries
          debugPrint('[SuspectedLocationDatabase] Error parsing row: $e');
          continue;
        }
      }
      
      return locations;
    } catch (e) {
      debugPrint('[SuspectedLocationDatabase] Error querying bounds: $e');
      return [];
    }
  }

  /// Get last fetch time
  Future<DateTime?> getLastFetchTime() async {
    try {
      final db = await database;
      
      final result = await db.query(
        _metaTableName,
        where: '$_metaColumnKey = ?',
        whereArgs: [_lastFetchKey],
      );
      
      if (result.isNotEmpty) {
        final value = result.first[_metaColumnValue] as String;
        return DateTime.fromMillisecondsSinceEpoch(int.parse(value));
      }
      
      return null;
    } catch (e) {
      debugPrint('[SuspectedLocationDatabase] Error getting last fetch time: $e');
      return null;
    }
  }

  /// Get total count of entries
  Future<int> getTotalCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('[SuspectedLocationDatabase] Error getting total count: $e');
      return 0;
    }
  }

  /// Check if database has data
  Future<bool> hasData() async {
    final count = await getTotalCount();
    return count > 0;
  }

  /// Close database connection
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
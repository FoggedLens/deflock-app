import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

import '../models/osm_node.dart';
import 'node_spatial_cache.dart';

/// SQLite write-behind persistence for the node spatial cache.
/// Persists Overpass-fetched nodes so they survive app restarts.
class NodeCacheDatabase {
  static final NodeCacheDatabase _instance = NodeCacheDatabase._();
  factory NodeCacheDatabase() => _instance;
  NodeCacheDatabase._();

  @visibleForTesting
  NodeCacheDatabase.forTesting();

  Database? _database;
  static const String _dbName = 'node_cache.db';
  static const int _dbVersion = 1;

  /// Initialize the database
  Future<void> init() async {
    if (_database != null) return;

    try {
      final dbPath = await getDatabasesPath();
      final fullPath = path.join(dbPath, _dbName);

      debugPrint('[NodeCacheDatabase] Initializing database at $fullPath');

      _database = await openDatabase(
        fullPath,
        version: _dbVersion,
        onCreate: _createTables,
      );

      debugPrint('[NodeCacheDatabase] Database initialized successfully');
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error initializing database: $e');
      rethrow;
    }
  }

  /// Create database tables
  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE nodes (
        id INTEGER PRIMARY KEY,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        tags TEXT NOT NULL,
        is_constrained INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_node_lat_lng ON nodes (lat, lng)
    ''');

    await db.execute('''
      CREATE TABLE cached_areas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        south REAL NOT NULL,
        west REAL NOT NULL,
        north REAL NOT NULL,
        east REAL NOT NULL,
        fetched_at INTEGER NOT NULL
      )
    ''');
  }

  /// Batch upsert nodes, filtering out negative IDs and underscore-prefixed tags.
  Future<void> insertNodes(List<OsmNode> nodes) async {
    final db = _database;
    if (db == null) return;

    try {
      const batchSize = 1000;
      await db.transaction((txn) async {
        var batch = txn.batch();
        var count = 0;

        for (final node in nodes) {
          if (node.id <= 0) continue;

          // Strip underscore-prefixed tags (transient markers)
          final persistTags = Map<String, String>.fromEntries(
            node.tags.entries.where((e) => !e.key.startsWith('_')),
          );

          batch.insert(
            'nodes',
            {
              'id': node.id,
              'lat': node.coord.latitude,
              'lng': node.coord.longitude,
              'tags': jsonEncode(persistTags),
              'is_constrained': node.isConstrained ? 1 : 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          count++;
          if (count % batchSize == 0) {
            await batch.commit(noResult: true);
            batch = txn.batch();
          }
        }

        if (count % batchSize != 0) {
          await batch.commit(noResult: true);
        }
      });
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error inserting nodes: $e');
    }
  }

  /// Insert a cached area record, removing any older entries it fully covers.
  Future<void> insertCachedArea(LatLngBounds bounds, DateTime fetchedAt) async {
    final db = _database;
    if (db == null) return;

    try {
      await db.transaction((txn) async {
        // Remove older areas fully contained by the new one
        await txn.delete(
          'cached_areas',
          where: 'south >= ? AND north <= ? AND west >= ? AND east <= ?',
          whereArgs: [bounds.south, bounds.north, bounds.west, bounds.east],
        );

        await txn.insert('cached_areas', {
          'south': bounds.south,
          'west': bounds.west,
          'north': bounds.north,
          'east': bounds.east,
          'fetched_at': fetchedAt.millisecondsSinceEpoch,
        });
      });
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error inserting cached area: $e');
    }
  }

  /// Load all nodes from the database for cache hydration.
  Future<List<OsmNode>> loadAllNodes() async {
    final db = _database;
    if (db == null) return [];

    try {
      final rows = await db.query('nodes');
      return rows.map((row) {
        final tagsJson = jsonDecode(row['tags'] as String) as Map<String, dynamic>;
        final tags = tagsJson.map((k, v) => MapEntry(k, v.toString()));

        return OsmNode(
          id: row['id'] as int,
          coord: LatLng((row['lat'] as num).toDouble(), (row['lng'] as num).toDouble()),
          tags: tags,
          isConstrained: (row['is_constrained'] as int) == 1,
        );
      }).toList();
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error loading nodes: $e');
      return [];
    }
  }

  /// Load non-expired cached areas.
  Future<List<CachedArea>> loadCachedAreas({required Duration ttl}) async {
    final db = _database;
    if (db == null) return [];

    try {
      final cutoff = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
      final rows = await db.query(
        'cached_areas',
        where: 'fetched_at >= ?',
        whereArgs: [cutoff],
      );

      return rows.map((row) {
        return CachedArea(
          LatLngBounds(
            LatLng((row['south'] as num).toDouble(), (row['west'] as num).toDouble()),
            LatLng((row['north'] as num).toDouble(), (row['east'] as num).toDouble()),
          ),
          DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
        );
      }).toList();
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error loading cached areas: $e');
      return [];
    }
  }

  /// Delete expired areas and orphaned nodes (nodes not covered by any remaining area).
  /// Uses a NOT EXISTS subquery to avoid SQLite bind-variable limits when many areas remain.
  Future<void> deleteExpiredData({required Duration ttl}) async {
    final db = _database;
    if (db == null) return;

    try {
      final cutoff = DateTime.now().subtract(ttl).millisecondsSinceEpoch;

      await db.transaction((txn) async {
        // Delete expired areas
        final deletedCount = await txn.delete(
          'cached_areas',
          where: 'fetched_at < ?',
          whereArgs: [cutoff],
        );

        if (deletedCount == 0) return;

        debugPrint('[NodeCacheDatabase] Deleted $deletedCount expired areas');

        // Check if any areas remain
        final remaining = await txn.rawQuery('SELECT COUNT(*) as cnt FROM cached_areas');
        final count = Sqflite.firstIntValue(remaining) ?? 0;

        if (count == 0) {
          // No areas left — delete all nodes
          final nodeCount = await txn.delete('nodes');
          debugPrint('[NodeCacheDatabase] Deleted all $nodeCount orphaned nodes');
          return;
        }

        // Use a subquery join to delete orphaned nodes without bind-variable limits
        final orphanCount = await txn.rawDelete('''
          DELETE FROM nodes WHERE NOT EXISTS (
            SELECT 1 FROM cached_areas
            WHERE nodes.lat >= cached_areas.south
              AND nodes.lat <= cached_areas.north
              AND nodes.lng >= cached_areas.west
              AND nodes.lng <= cached_areas.east
          )
        ''');
        debugPrint('[NodeCacheDatabase] Deleted $orphanCount orphaned nodes');
      });
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error deleting expired data: $e');
    }
  }

  /// Delete cached areas that overlap with the given bounds (containment in either direction).
  Future<void> deleteOverlappingAreas(LatLngBounds bounds) async {
    final db = _database;
    if (db == null) return;

    try {
      // Areas fully contained by bounds OR that fully contain bounds
      final deleted = await db.delete(
        'cached_areas',
        where: '(south >= ? AND north <= ? AND west >= ? AND east <= ?) OR '
            '(south <= ? AND north >= ? AND west <= ? AND east >= ?)',
        whereArgs: [
          bounds.south, bounds.north, bounds.west, bounds.east,
          bounds.south, bounds.north, bounds.west, bounds.east,
        ],
      );
      if (deleted > 0) {
        debugPrint('[NodeCacheDatabase] Deleted $deleted overlapping areas');
      }
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error deleting overlapping areas: $e');
    }
  }

  /// Clear all cached data.
  Future<void> clearAll() async {
    final db = _database;
    if (db == null) return;

    try {
      await db.transaction((txn) async {
        await txn.delete('nodes');
        await txn.delete('cached_areas');
      });
      debugPrint('[NodeCacheDatabase] All data cleared');
    } catch (e) {
      debugPrint('[NodeCacheDatabase] Error clearing data: $e');
    }
  }

  /// Close the database connection.
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}

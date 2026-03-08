import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/osm_node.dart';
import 'node_cache_database.dart';

const Distance _distance = Distance();

/// Simple spatial cache that tracks which areas have been successfully fetched.
/// Backed by SQLite for persistence across app restarts.
class NodeSpatialCache {
  static final NodeSpatialCache _instance = NodeSpatialCache._();
  factory NodeSpatialCache() => _instance;
  NodeSpatialCache._();

  @visibleForTesting
  NodeSpatialCache.forTesting();

  final List<CachedArea> _fetchedAreas = [];
  final Map<int, OsmNode> _nodes = {}; // nodeId -> node

  NodeCacheDatabase? _database;

  /// How old cached data can be before it's considered stale (serve + background refresh).
  static const Duration freshThreshold = Duration(hours: 1);

  /// How old cached data can be before it's expired and pruned from SQLite.
  static const Duration expiryTtl = Duration(days: 7);

  /// Initialize SQLite persistence: prune expired data, then hydrate in-memory cache.
  /// No-ops if already initialized to avoid wiping in-memory data accumulated
  /// during the session.
  Future<void> initPersistence() async {
    if (_database != null) return;

    final db = NodeCacheDatabase();
    await db.init();
    _database = db;

    // Prune expired areas and orphaned nodes
    await db.deleteExpiredData(ttl: expiryTtl);

    // Load surviving data into memory
    final areas = await db.loadCachedAreas(ttl: expiryTtl);
    final nodes = await db.loadAllNodes();

    _fetchedAreas.addAll(areas);
    _fetchedAreasView = null;
    for (final node in nodes) {
      _nodes[node.id] = node;
    }

    debugPrint('[NodeSpatialCache] Hydrated from SQLite: ${areas.length} areas, ${nodes.length} nodes');
  }

  /// Check if we have cached data covering the given bounds
  bool hasDataFor(LatLngBounds bounds) {
    return _fetchedAreas.any((area) => area.bounds.containsBounds(bounds));
  }

  /// Whether a cached area's data is still within [freshThreshold].
  bool _isFreshAt(CachedArea area, DateTime now) =>
      now.difference(area.fetchedAt) <= freshThreshold;

  /// Check if we have fresh (non-stale) cached data covering the given bounds.
  bool hasFreshDataFor(LatLngBounds bounds) {
    final now = DateTime.now();
    return _fetchedAreas.any((area) =>
        area.bounds.containsBounds(bounds) && _isFreshAt(area, now));
  }

  /// Return the original cached bounds of the first stale area covering [bounds],
  /// or null if no stale coverage exists.  The returned bounds include the
  /// original 1.2x expansion so the background refresh targets the same area.
  LatLngBounds? staleAreaFor(LatLngBounds bounds) {
    final now = DateTime.now();
    for (final area in _fetchedAreas) {
      if (area.bounds.containsBounds(bounds) && !_isFreshAt(area, now)) {
        return area.bounds;
      }
    }
    return null;
  }

  /// Record that we successfully fetched data for this area.
  /// Removes older entries that the new area fully subsumes to bound list growth.
  void markAreaAsFetched(LatLngBounds bounds, List<OsmNode> nodes) {
    final now = DateTime.now();

    // Remove existing entries that the new area fully covers (dedup/compact)
    _fetchedAreas.removeWhere((existing) => bounds.containsBounds(existing.bounds));

    // Add the fetched area
    _fetchedAreas.add(CachedArea(bounds, now));
    _fetchedAreasView = null; // Invalidate cached view

    // Update nodes in cache
    for (final node in nodes) {
      _nodes[node.id] = node;
    }

    debugPrint('[NodeSpatialCache] Cached ${nodes.length} nodes for area ${bounds.south.toStringAsFixed(3)},${bounds.west.toStringAsFixed(3)} to ${bounds.north.toStringAsFixed(3)},${bounds.east.toStringAsFixed(3)}');
    debugPrint('[NodeSpatialCache] Total areas cached: ${_fetchedAreas.length}, total nodes: ${_nodes.length}');

    // Write-through to SQLite (fire-and-forget)
    _database?.insertNodes(nodes);
    _database?.insertCachedArea(bounds, now);
  }

  /// Get all cached nodes within the given bounds
  List<OsmNode> getNodesFor(LatLngBounds bounds) {
    return _nodes.values
        .where((node) => bounds.contains(node.coord))
        .toList();
  }

  /// Add or update individual nodes (for upload queue integration)
  void addOrUpdateNodes(List<OsmNode> nodes) {
    for (final node in nodes) {
      final existing = _nodes[node.id];
      if (existing != null) {
        // Preserve any tags starting with underscore when updating existing nodes
        final mergedTags = Map<String, String>.from(node.tags);
        for (final entry in existing.tags.entries) {
          if (entry.key.startsWith('_')) {
            mergedTags[entry.key] = entry.value;
          }
        }
        _nodes[node.id] = OsmNode(
          id: node.id,
          coord: node.coord,
          tags: mergedTags,
          isConstrained: node.isConstrained,
        );
      } else {
        _nodes[node.id] = node;
      }
    }
  }

  /// Remove a node by ID (for deletions)
  void removeNodeById(int nodeId) {
    if (_nodes.remove(nodeId) != null) {
      debugPrint('[NodeSpatialCache] Removed node $nodeId from cache');
    }
  }

  /// Get a specific node by ID (returns null if not found)
  OsmNode? getNodeById(int nodeId) {
    return _nodes[nodeId];
  }

  /// Remove the _pending_edit marker from a specific node
  void removePendingEditMarker(int nodeId) {
    final node = _nodes[nodeId];
    if (node != null && node.tags.containsKey('_pending_edit')) {
      final cleanTags = Map<String, String>.from(node.tags);
      cleanTags.remove('_pending_edit');

      _nodes[nodeId] = OsmNode(
        id: node.id,
        coord: node.coord,
        tags: cleanTags,
        isConstrained: node.isConstrained,
      );
    }
  }

  /// Remove the _pending_deletion marker from a specific node
  void removePendingDeletionMarker(int nodeId) {
    final node = _nodes[nodeId];
    if (node != null && node.tags.containsKey('_pending_deletion')) {
      final cleanTags = Map<String, String>.from(node.tags);
      cleanTags.remove('_pending_deletion');

      _nodes[nodeId] = OsmNode(
        id: node.id,
        coord: node.coord,
        tags: cleanTags,
        isConstrained: node.isConstrained,
      );
    }
  }

  /// Remove a specific temporary node by its ID
  void removeTempNodeById(int tempNodeId) {
    if (tempNodeId >= 0) {
      debugPrint('[NodeSpatialCache] Warning: Attempted to remove non-temp node ID $tempNodeId');
      return;
    }

    if (_nodes.remove(tempNodeId) != null) {
      debugPrint('[NodeSpatialCache] Removed temp node $tempNodeId from cache');
    }
  }

  /// Find nodes within distance of a coordinate (for proximity warnings)
  List<OsmNode> findNodesWithinDistance(LatLng coord, double distanceMeters, {int? excludeNodeId}) {
    final nearbyNodes = <OsmNode>[];

    for (final node in _nodes.values) {
      // Skip the excluded node
      if (excludeNodeId != null && node.id == excludeNodeId) {
        continue;
      }

      // Skip nodes marked for deletion
      if (node.tags.containsKey('_pending_deletion')) {
        continue;
      }

      final distanceInMeters = _distance.as(LengthUnit.Meter, coord, node.coord);
      if (distanceInMeters <= distanceMeters) {
        nearbyNodes.add(node);
      }
    }

    return nearbyNodes;
  }

  /// Invalidate cached areas where one fully contains the other.
  /// Nodes are kept (they'll be refreshed by the subsequent fetch).
  void invalidateArea(LatLngBounds bounds) {
    final before = _fetchedAreas.length;
    _fetchedAreas.removeWhere((area) =>
        area.bounds.containsBounds(bounds) || bounds.containsBounds(area.bounds));
    _fetchedAreasView = null;
    _database?.deleteOverlappingAreas(bounds);
    debugPrint('[NodeSpatialCache] Invalidated ${before - _fetchedAreas.length} areas overlapping ${bounds.south.toStringAsFixed(3)},${bounds.west.toStringAsFixed(3)} to ${bounds.north.toStringAsFixed(3)},${bounds.east.toStringAsFixed(3)}');
  }

  /// Clear all cached data
  void clear() {
    _fetchedAreas.clear();
    _fetchedAreasView = null;
    _nodes.clear();
    _database?.clearAll();
    debugPrint('[NodeSpatialCache] Cache cleared');
  }

  /// Get fetched areas with timestamps (for coverage overlay visualization).
  /// Cached to avoid allocating a new wrapper on every map rebuild.
  List<CachedArea>? _fetchedAreasView;
  List<CachedArea> get fetchedAreas =>
      _fetchedAreasView ??= List.unmodifiable(_fetchedAreas);

  /// Get cache statistics for debugging
  CacheStats get stats => CacheStats(
    areasCount: _fetchedAreas.length,
    nodesCount: _nodes.length,
  );
}

/// Represents an area that has been successfully fetched
class CachedArea {
  final LatLngBounds bounds;
  final DateTime fetchedAt;

  CachedArea(this.bounds, this.fetchedAt);
}

/// Cache statistics for debugging
class CacheStats {
  final int areasCount;
  final int nodesCount;

  CacheStats({required this.areasCount, required this.nodesCount});

  @override
  String toString() => 'CacheStats(areas: $areasCount, nodes: $nodesCount)';
}

/// Extension to check if one bounds completely contains another
extension LatLngBoundsExtension on LatLngBounds {
  bool containsBounds(LatLngBounds other) {
    return north >= other.north &&
           south <= other.south &&
           east >= other.east &&
           west <= other.west;
  }
}

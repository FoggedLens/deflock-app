import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/osm_node.dart';

const Distance _distance = Distance();

/// Simple spatial cache that tracks which areas have been successfully fetched.
/// No temporal expiration - data stays cached until app restart or explicit clear.
class NodeSpatialCache {
  static final NodeSpatialCache _instance = NodeSpatialCache._();
  factory NodeSpatialCache() => _instance;
  NodeSpatialCache._();

  @visibleForTesting
  NodeSpatialCache.forTesting();

  final List<CachedArea> _fetchedAreas = [];
  final Map<int, OsmNode> _nodes = {}; // nodeId -> node

  /// Check if we have cached data covering the given bounds
  bool hasDataFor(LatLngBounds bounds) {
    return _fetchedAreas.any((area) => area.bounds.containsBounds(bounds));
  }

  /// Record that we successfully fetched data for this area
  void markAreaAsFetched(LatLngBounds bounds, List<OsmNode> nodes) {
    // Add the fetched area
    _fetchedAreas.add(CachedArea(bounds, DateTime.now()));
    
    // Update nodes in cache
    for (final node in nodes) {
      _nodes[node.id] = node;
    }
    
    debugPrint('[NodeSpatialCache] Cached ${nodes.length} nodes for area ${bounds.south.toStringAsFixed(3)},${bounds.west.toStringAsFixed(3)} to ${bounds.north.toStringAsFixed(3)},${bounds.east.toStringAsFixed(3)}');
    debugPrint('[NodeSpatialCache] Total areas cached: ${_fetchedAreas.length}, total nodes: ${_nodes.length}');
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

  /// Clear all cached data
  void clear() {
    _fetchedAreas.clear();
    _nodes.clear();
    debugPrint('[NodeSpatialCache] Cache cleared');
  }

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
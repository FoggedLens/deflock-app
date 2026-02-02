import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/osm_node.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

const Distance _distance = Distance();

class NodeCache {
  // Singleton instance
  static final NodeCache instance = NodeCache._internal();
  factory NodeCache() => instance;
  NodeCache._internal();

  final Map<int, OsmNode> _nodes = {};

  /// Add or update a batch of nodes in the cache.
  /// TODO: Consider moving to compute() if cache operations cause ANR
  void addOrUpdate(List<OsmNode> nodes) {
    for (var node in nodes) {
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
          isConstrained: node.isConstrained, // Preserve constraint information
        );
      } else {
        _nodes[node.id] = node;
      }
    }
  }

  /// Query for all cached nodes currently within the given LatLngBounds.
  List<OsmNode> queryByBounds(LatLngBounds bounds) {
    return _nodes.values
        .where((node) => _inBounds(node.coord, bounds))
        .toList();
  }

  /// Retrieve all cached nodes.
  List<OsmNode> getAll() => _nodes.values.toList();

  /// Optionally clear the cache (rarely needed)
  void clear() => _nodes.clear();

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
        isConstrained: node.isConstrained, // Preserve constraint information
      );
    }
  }

  /// Remove the _pending_deletion marker from a specific node (when deletion is cancelled)
  void removePendingDeletionMarker(int nodeId) {
    final node = _nodes[nodeId];
    if (node != null && node.tags.containsKey('_pending_deletion')) {
      final cleanTags = Map<String, String>.from(node.tags);
      cleanTags.remove('_pending_deletion');
      
      _nodes[nodeId] = OsmNode(
        id: node.id,
        coord: node.coord,
        tags: cleanTags,
        isConstrained: node.isConstrained, // Preserve constraint information
      );
    }
  }

  /// Remove a node by ID from the cache (used for successful deletions)
  void removeNodeById(int nodeId) {
    if (_nodes.remove(nodeId) != null) {
      debugPrint('[NodeCache] Removed node $nodeId from cache (successful deletion)');
    }
  }
  
  /// Remove temporary nodes (negative IDs) with _pending_upload marker at the given coordinate
  /// This is used when a real node ID is assigned to clean up temp placeholders
  void removeTempNodesByCoordinate(LatLng coord, {double tolerance = 0.00001}) {
    final nodesToRemove = <int>[];
    
    for (final entry in _nodes.entries) {
      final nodeId = entry.key;
      final node = entry.value;
      
      // Only consider temp nodes (negative IDs) with pending upload marker
      if (nodeId < 0 && 
          node.tags.containsKey('_pending_upload') &&
          _coordsMatch(node.coord, coord, tolerance)) {
        nodesToRemove.add(nodeId);
      }
    }
    
    for (final nodeId in nodesToRemove) {
      _nodes.remove(nodeId);
    }
    
    if (nodesToRemove.isNotEmpty) {
      debugPrint('[NodeCache] Removed ${nodesToRemove.length} temp nodes at coordinate ${coord.latitude}, ${coord.longitude}');
    }
  }

  /// Remove a specific temporary node by its ID (for queue item-specific cleanup)
  void removeTempNodeById(int tempNodeId) {
    if (tempNodeId >= 0) {
      debugPrint('[NodeCache] Warning: Attempted to remove non-temp node ID $tempNodeId');
      return;
    }
    
    if (_nodes.remove(tempNodeId) != null) {
      debugPrint('[NodeCache] Removed specific temp node $tempNodeId from cache');
    }
  }

  /// Get a specific node by ID (returns null if not found)
  OsmNode? getNodeById(int nodeId) {
    return _nodes[nodeId];
  }
  
  /// Check if two coordinates match within tolerance
  bool _coordsMatch(LatLng coord1, LatLng coord2, double tolerance) {
    return (coord1.latitude - coord2.latitude).abs() < tolerance &&
           (coord1.longitude - coord2.longitude).abs() < tolerance;
  }

  /// Find nodes within the specified distance (in meters) of the given coordinate
  /// Excludes nodes with the excludeNodeId (useful when checking proximity for edited nodes)
  /// Includes pending nodes to warn about potential duplicates
  List<OsmNode> findNodesWithinDistance(LatLng coord, double distanceMeters, {int? excludeNodeId}) {
    final nearbyNodes = <OsmNode>[];
    
    for (final node in _nodes.values) {
      // Skip the excluded node (typically the node being edited)
      if (excludeNodeId != null && node.id == excludeNodeId) {
        continue;
      }
      
      // Include all nodes (real and pending) to catch potential duplicates
      // Only skip nodes marked for deletion since they won't actually exist after processing
      if (node.tags.containsKey('_pending_deletion')) {
        continue;
      }
      
      final distance = _distance.as(LengthUnit.Meter, coord, node.coord);
      if (distance <= distanceMeters) {
        nearbyNodes.add(node);
      }
    }
    
    return nearbyNodes;
  }

  /// Utility: point-in-bounds for coordinates
  bool _inBounds(LatLng coord, LatLngBounds bounds) {
    return coord.latitude >= bounds.southWest.latitude &&
        coord.latitude <= bounds.northEast.latitude &&
        coord.longitude >= bounds.southWest.longitude &&
        coord.longitude <= bounds.northEast.longitude;
  }
}

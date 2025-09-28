import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import '../../models/osm_camera_node.dart';
import '../../models/node_profile.dart';
import '../offline_area_service.dart';
import '../offline_areas/offline_area_models.dart';

/// Fetch surveillance nodes from all offline areas intersecting the bounds/profile list.
Future<List<OsmCameraNode>> fetchLocalNodes({
  required LatLngBounds bounds,
  required List<NodeProfile> profiles,
  int? maxNodes,
}) async {
  final areas = OfflineAreaService().offlineAreas;
  final Map<int, OsmCameraNode> deduped = {};

  debugPrint('[fetchLocalNodes] Checking ${areas.length} offline areas for nodes');
  debugPrint('[fetchLocalNodes] Requested bounds: ${bounds.southWest.latitude},${bounds.southWest.longitude} to ${bounds.northEast.latitude},${bounds.northEast.longitude}');
  debugPrint('[fetchLocalNodes] Using ${profiles.length} profiles: ${profiles.map((p) => p.name).join(', ')}');

  for (final area in areas) {
    debugPrint('[fetchLocalNodes] Area ${area.name} (${area.id}): status=${area.status}');
    if (area.status != OfflineAreaStatus.complete) {
      debugPrint('[fetchLocalNodes] Skipping area ${area.name} - status is ${area.status}');
      continue;
    }
    debugPrint('[fetchLocalNodes] Area ${area.name} bounds: ${area.bounds.southWest.latitude},${area.bounds.southWest.longitude} to ${area.bounds.northEast.latitude},${area.bounds.northEast.longitude}');
    if (!area.bounds.isOverlapping(bounds)) {
      debugPrint('[fetchLocalNodes] Skipping area ${area.name} - bounds do not overlap');
      continue;
    }

    final nodes = await _loadAreaNodes(area);
    debugPrint('[fetchLocalNodes] Area ${area.name} loaded ${nodes.length} nodes from storage');
    
    int nodesBefore = deduped.length;
    int dedupFiltered = 0;
    int boundsFiltered = 0;
    int profileFiltered = 0;
    
    for (final node in nodes) {
      // Deduplicate by node ID, preferring the first occurrence
      if (deduped.containsKey(node.id)) {
        dedupFiltered++;
        continue;
      }
      // Within view bounds?
      if (!_pointInBounds(node.coord, bounds)) {
        boundsFiltered++;
        if (boundsFiltered <= 3) { // Log first few for debugging
          debugPrint('[fetchLocalNodes] Node ${node.id} at ${node.coord.latitude},${node.coord.longitude} outside bounds ${bounds.southWest.latitude},${bounds.southWest.longitude} to ${bounds.northEast.latitude},${bounds.northEast.longitude}');
        }
        continue;
      }
      // Profile filter if used
      if (profiles.isNotEmpty && !_matchesAnyProfile(node, profiles)) {
        profileFiltered++;
        if (profileFiltered <= 3) { // Log first few for debugging
          debugPrint('[fetchLocalNodes] Node ${node.id} tags ${node.tags} don\'t match any of ${profiles.length} profiles');
        }
        continue;
      }
      deduped[node.id] = node;
    }
    int nodesAdded = deduped.length - nodesBefore;
    debugPrint('[fetchLocalNodes] Area ${area.name}: dedup filtered: $dedupFiltered, bounds filtered: $boundsFiltered, profile filtered: $profileFiltered');
    debugPrint('[fetchLocalNodes] Area ${area.name} contributed ${nodesAdded} nodes after filtering');
  }

  final out = deduped.values.take(maxNodes ?? deduped.length).toList();
  debugPrint('[fetchLocalNodes] Returning ${out.length} nodes total');
  return out;
}

// Try in-memory first, else load from disk
Future<List<OsmCameraNode>> _loadAreaNodes(OfflineArea area) async {
  if (area.nodes.isNotEmpty) {
    debugPrint('[_loadAreaNodes] Area ${area.name} has ${area.nodes.length} nodes in memory');
    return area.nodes;
  }
  
  // Try new nodes.json first, fall back to legacy cameras.json for backward compatibility
  final nodeFile = File('${area.directory}/nodes.json');
  final legacyCameraFile = File('${area.directory}/cameras.json');
  
  File fileToLoad;
  if (await nodeFile.exists()) {
    fileToLoad = nodeFile;
    debugPrint('[_loadAreaNodes] Found new node file: ${fileToLoad.path}');
  } else if (await legacyCameraFile.exists()) {
    fileToLoad = legacyCameraFile;
    debugPrint('[_loadAreaNodes] Found legacy camera file: ${fileToLoad.path}');
  } else {
    debugPrint('[_loadAreaNodes] No node file exists for area ${area.name}');
    debugPrint('[_loadAreaNodes] Checked: ${nodeFile.path}');
    debugPrint('[_loadAreaNodes] Checked: ${legacyCameraFile.path}');
    return [];
  }
  
  try {
    final str = await fileToLoad.readAsString();
    final jsonList = jsonDecode(str) as List;
    final nodes = jsonList.map((e) => OsmCameraNode.fromJson(e)).toList();
    debugPrint('[_loadAreaNodes] Loaded ${nodes.length} nodes from ${fileToLoad.path}');
    return nodes;
  } catch (e) {
    debugPrint('[_loadAreaNodes] Error loading nodes from ${fileToLoad.path}: $e');
    return [];
  }
}

bool _pointInBounds(LatLng pt, LatLngBounds bounds) {
  return pt.latitude  >= bounds.southWest.latitude &&
         pt.latitude  <= bounds.northEast.latitude &&
         pt.longitude >= bounds.southWest.longitude &&
         pt.longitude <= bounds.northEast.longitude;
}

bool _matchesAnyProfile(OsmCameraNode node, List<NodeProfile> profiles) {
  for (final prof in profiles) {
    if (_nodeMatchesProfile(node, prof)) return true;
  }
  return false;
}

bool _nodeMatchesProfile(OsmCameraNode node, NodeProfile profile) {
  for (final e in profile.tags.entries) {
    if (node.tags[e.key] != e.value) return false; // All profile tags must match
  }
  return true;
}

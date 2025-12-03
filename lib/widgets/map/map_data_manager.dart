import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';

import '../../models/osm_node.dart';
import '../../app_state.dart';
import '../camera_provider_with_cache.dart';
import '../../dev_config.dart';

/// Manages data fetching, filtering, and node limit logic for the map.
/// Handles profile changes, zoom level restrictions, and node rendering limits.
class MapDataManager {
  // Track node limit state for parent notification
  bool _lastNodeLimitState = false;

  /// Get minimum zoom level for node fetching based on upload mode
  int getMinZoomForNodes(UploadMode uploadMode) {
    // OSM API (sandbox mode) needs higher zoom level due to bbox size limits
    if (uploadMode == UploadMode.sandbox) {
      return kOsmApiMinZoomLevel;
    } else {
      return kNodeMinZoomLevel;
    }
  }

  /// Get nodes to render based on current map state
  /// Returns a MapDataResult containing all relevant node data and limit state
  MapDataResult getNodesForRendering({
    required double currentZoom,
    required LatLngBounds? mapBounds,
    required UploadMode uploadMode,
    required int maxNodes,
    void Function(bool isLimited)? onNodeLimitChanged,
  }) {
    final minZoom = getMinZoomForNodes(uploadMode);
    List<OsmNode> allNodes;
    List<OsmNode> nodesToRender;
    bool isLimitActive = false;
    
    if (currentZoom >= minZoom) {
      // Above minimum zoom - get cached nodes directly (no Provider needed)
      allNodes = (mapBounds != null)
          ? CameraProviderWithCache.instance.getCachedNodesForBounds(mapBounds)
          : <OsmNode>[];
      
      // Filter out invalid coordinates before applying limit
      final validNodes = allNodes.where((node) {
        return (node.coord.latitude != 0 || node.coord.longitude != 0) &&
               node.coord.latitude.abs() <= 90 && 
               node.coord.longitude.abs() <= 180;
      }).toList();
      
      // Apply rendering limit to prevent UI lag
      if (validNodes.length > maxNodes) {
        nodesToRender = validNodes.take(maxNodes).toList();
        isLimitActive = true;
        debugPrint('[MapDataManager] Node limit active: rendering ${nodesToRender.length} of ${validNodes.length} devices');
      } else {
        nodesToRender = validNodes;
        isLimitActive = false;
      }
    } else {
      // Below minimum zoom - don't render any nodes
      allNodes = <OsmNode>[];
      nodesToRender = <OsmNode>[];
      isLimitActive = false;
    }
    
    // Notify parent if limit state changed (for button disabling)
    if (isLimitActive != _lastNodeLimitState) {
      _lastNodeLimitState = isLimitActive;
      // Schedule callback after build completes to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onNodeLimitChanged?.call(isLimitActive);
      });
    }

    return MapDataResult(
      allNodes: allNodes,
      nodesToRender: nodesToRender,
      isLimitActive: isLimitActive,
      validNodesCount: isLimitActive ? allNodes.where((node) {
        return (node.coord.latitude != 0 || node.coord.longitude != 0) &&
               node.coord.latitude.abs() <= 90 && 
               node.coord.longitude.abs() <= 180;
      }).length : 0,
    );
  }

  /// Show zoom warning if user is below minimum zoom level
  void showZoomWarningIfNeeded(BuildContext context, double currentZoom, UploadMode uploadMode) {
    final minZoom = getMinZoomForNodes(uploadMode);
    
    // Only show warning once per zoom level to avoid spam
    if (currentZoom.floor() == (minZoom - 1)) {
      final message = uploadMode == UploadMode.sandbox 
          ? 'Zoom to level $minZoom or higher to see nodes in sandbox mode (OSM API bbox limit)'
          : 'Zoom to level $minZoom or higher to see surveillance nodes';
      
      // Show a brief snackbar
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

/// Result object containing node data and rendering state
class MapDataResult {
  final List<OsmNode> allNodes;
  final List<OsmNode> nodesToRender;
  final bool isLimitActive;
  final int validNodesCount;

  const MapDataResult({
    required this.allNodes,
    required this.nodesToRender,
    required this.isLimitActive,
    required this.validNodesCount,
  });
}
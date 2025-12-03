import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/osm_node.dart';
import '../../app_state.dart';
import '../../state/session_state.dart';
import '../../dev_config.dart';
import 'direction_cones.dart';

/// Builds overlay layers including direction cones, edit lines, selected location bounds, and route paths.
class OverlayLayerBuilder {
  
  /// Build all overlay layers for the map
  static List<Widget> buildOverlayLayers({
    required List<OsmNode> nodesToRender,
    required double currentZoom,
    required AddNodeSession? session,
    required EditNodeSession? editSession,
    required AppState appState,
    required BuildContext context,
  }) {
    final layers = <Widget>[];

    // Direction cones (polygons)
    final overlays = DirectionConesBuilder.buildDirectionCones(
      cameras: nodesToRender,
      zoom: currentZoom,
      session: session,
      editSession: editSession,
      context: context,
    );

    // Add suspected location bounds if one is selected
    if (appState.selectedSuspectedLocation != null) {
      final selectedLocation = appState.selectedSuspectedLocation!;
      if (selectedLocation.bounds.isNotEmpty) {
        overlays.add(
          Polygon(
            points: selectedLocation.bounds,
            color: Colors.orange.withOpacity(0.3),
            borderColor: Colors.orange,
            borderStrokeWidth: 2.0,
          ),
        );
      }
    }

    // Add polygon layer
    layers.add(PolygonLayer(polygons: overlays));

    // Build edit lines connecting original nodes to their edited positions
    final editLines = _buildEditLines(nodesToRender);
    if (editLines.isNotEmpty) {
      layers.add(PolylineLayer(polylines: editLines));
    }

    // Build route path visualization
    final routeLines = _buildRouteLines(appState);
    if (routeLines.isNotEmpty) {
      layers.add(PolylineLayer(polylines: routeLines));
    }

    return layers;
  }

  /// Build polylines connecting original cameras to their edited positions
  static List<Polyline> _buildEditLines(List<OsmNode> nodes) {
    final lines = <Polyline>[];
    
    // Create a lookup map of original node IDs to their coordinates
    final originalNodes = <int, LatLng>{};
    for (final node in nodes) {
      if (node.tags['_pending_edit'] == 'true') {
        originalNodes[node.id] = node.coord;
      }
    }
    
    // Find edited nodes and draw lines to their originals
    for (final node in nodes) {
      final originalIdStr = node.tags['_original_node_id'];
      if (originalIdStr != null && node.tags['_pending_upload'] == 'true') {
        final originalId = int.tryParse(originalIdStr);
        final originalCoord = originalId != null ? originalNodes[originalId] : null;
        
        if (originalCoord != null) {
          lines.add(Polyline(
            points: [originalCoord, node.coord],
            color: kNodeRingColorPending,
            strokeWidth: 3.0,
          ));
        }
      }
    }
    
    return lines;
  }

  /// Build route path visualization
  static List<Polyline> _buildRouteLines(AppState appState) {
    final routeLines = <Polyline>[];
    if (appState.routePath != null && appState.routePath!.length > 1) {
      // Show route line during overview or active route
      if (appState.showingOverview || appState.isInRouteMode) {
        routeLines.add(Polyline(
          points: appState.routePath!,
          color: Colors.blue,
          strokeWidth: 4.0,
        ));
      }
    }
    return routeLines;
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/osm_node.dart';
import '../../models/suspected_location.dart';
import '../../models/search_result.dart';

/// Handles map interaction events including node taps, suspected location taps,
/// and search result selection with appropriate map animations and state updates.
class MapInteractionHandler {

  /// Handle node tap with highlighting and map centering
  void handleNodeTap({
    required BuildContext context,
    required OsmNode node,
    required AnimatedMapController mapController,
    required Function(int?) onSelectedNodeChanged,
  }) {
    final appState = context.read<AppState>();
    
    // Disable follow-me when user taps a node
    appState.setFollowMeMode(FollowMeMode.off);
    
    // Set the selected node for highlighting
    onSelectedNodeChanged(node.id);
    
    // Center the map on the selected node with smooth animation
    try {
      mapController.animateTo(
        dest: node.coord,
        zoom: mapController.mapController.camera.zoom,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (e) {
      debugPrint('[MapInteractionHandler] Could not center map on node: $e');
    }
    
    // Start edit session for the node
    appState.startEditSession(node);
  }

  /// Handle suspected location tap with selection and highlighting
  void handleSuspectedLocationTap({
    required BuildContext context,
    required SuspectedLocation location,
    required AnimatedMapController mapController,
  }) {
    final appState = context.read<AppState>();
    
    debugPrint('[MapInteractionHandler] Suspected location tapped: ${location.ticketNo}');
    
    // Disable follow-me when user taps a suspected location
    appState.setFollowMeMode(FollowMeMode.off);
    
    // Select the suspected location for highlighting
    appState.selectSuspectedLocation(location);
    
    // Center the map on the suspected location
    try {
      mapController.animateTo(
        dest: location.centroid,
        zoom: mapController.mapController.camera.zoom.clamp(16.0, 18.0), // Zoom in if needed
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    } catch (e) {
      debugPrint('[MapInteractionHandler] Could not center map on suspected location: $e');
    }
  }

  /// Handle search result selection with map animation and routing setup
  void handleSearchResultSelection({
    required BuildContext context,
    required SearchResult result,
    required AnimatedMapController mapController,
  }) {
    final appState = context.read<AppState>();
    
    debugPrint('[MapInteractionHandler] Search result selected: ${result.displayName}');
    
    // Disable follow-me to prevent interference with selection
    appState.setFollowMeMode(FollowMeMode.off);
    
    // Update app state with the selection
    appState.selectSearchResult(result);
    
    // Animate to the selected location
    try {
      mapController.animateTo(
        dest: result.coordinates,
        zoom: 16.0, // Good zoom level for search results
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
      );
    } catch (e) {
      debugPrint('[MapInteractionHandler] Could not animate to search result: $e');
      // Fallback to immediate positioning
      try {
        mapController.mapController.move(result.coordinates, 16.0);
      } catch (_) {
        debugPrint('[MapInteractionHandler] Could not move to search result');
      }
    }
  }

  /// Clear selected node highlighting
  void clearSelectedNode({
    required Function(int?) onSelectedNodeChanged,
  }) {
    onSelectedNodeChanged(null);
  }
  
  /// Handle user gesture on map (clears selections)
  void handleUserGesture({
    required BuildContext context,
    required Function(int?) onSelectedNodeChanged,
  }) {
    final appState = context.read<AppState>();
    
    // Clear selected node highlighting
    onSelectedNodeChanged(null);
    
    // Clear suspected location selection
    appState.clearSuspectedLocationSelection();
  }
}
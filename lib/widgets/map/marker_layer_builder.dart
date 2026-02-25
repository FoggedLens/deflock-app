import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';

import '../../models/osm_node.dart';
import '../../models/suspected_location.dart';
import '../../app_state.dart';
import '../../dev_config.dart';
import '../camera_icon.dart';
import '../provisional_pin.dart';
import 'node_markers.dart';
import 'suspected_location_markers.dart';
import '../rf_detection_markers.dart';
import '../../models/rf_detection.dart';

/// Enumeration for different pin types in navigation
enum PinType { start, end }

/// Simple location pin widget for route visualization
class LocationPin extends StatelessWidget {
  final PinType type;
  
  const LocationPin({super.key, required this.type});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32.0,
      height: 32.0,
      decoration: BoxDecoration(
        color: type == PinType.start ? Colors.green : Colors.red,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(
        type == PinType.start ? Icons.play_arrow : Icons.stop,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}

/// Builds all marker layers for the map including surveillance nodes, suspected locations,
/// session markers, navigation pins, and route visualization.
class MarkerLayerBuilder {
  
  /// Build complete marker layers for the map
  static Widget buildMarkerLayers({
    required List<OsmNode> nodesToRender,
    required AnimatedMapController mapController,
    required AppState appState,
    required AddNodeSession? session,
    required EditNodeSession? editSession,
    required int? selectedNodeId,
    required LatLng? userLocation,
    required double currentZoom,
    required LatLngBounds? mapBounds,
    required Function(OsmNode)? onNodeTap,
    required Function(SuspectedLocation)? onSuspectedLocationTap,
    List<RfDetection>? rfDetections,
    Function(RfDetection)? onRfDetectionTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        
        // Determine if nodes should be dimmed and/or disabled
        final shouldDimNodes = appState.selectedSuspectedLocation != null ||
                               appState.isInSearchMode ||
                               appState.showingOverview;
        
        // Disable node interactions when navigation is in conflicting state
        final shouldDisableNodeTaps = appState.isInSearchMode || appState.showingOverview;
        
        final markers = NodeMarkersBuilder.buildNodeMarkers(
          nodes: nodesToRender,
          mapController: mapController.mapController,
          userLocation: userLocation,
          selectedNodeId: selectedNodeId,
          onNodeTap: onNodeTap, // Keep the original callback
          shouldDim: shouldDimNodes,
          enabled: !shouldDisableNodeTaps, // Use enabled parameter instead
        );

        // Build suspected location markers (respect same zoom and count limits as nodes)
        final suspectedLocationMarkers = <Marker>[];
        if (appState.suspectedLocationsEnabled && mapBounds != null && 
            currentZoom >= (appState.uploadMode == UploadMode.sandbox ? kOsmApiMinZoomLevel : kNodeMinZoomLevel)) {
          final suspectedLocations = appState.getSuspectedLocationsInBoundsSync(
            north: mapBounds.north,
            south: mapBounds.south,
            east: mapBounds.east,
            west: mapBounds.west,
          );
          
          // Apply same node count limit as surveillance nodes
          final maxNodes = appState.maxNodes;
          final limitedSuspectedLocations = suspectedLocations.take(maxNodes).toList();
          
          // Filter out suspected locations that are too close to real nodes
          final filteredSuspectedLocations = _filterSuspectedLocationsByProximity(
            suspectedLocations: limitedSuspectedLocations,
            realNodes: nodesToRender,
            minDistance: appState.suspectedLocationMinDistance,
          );
          
          suspectedLocationMarkers.addAll(
            SuspectedLocationMarkersBuilder.buildSuspectedLocationMarkers(
              locations: filteredSuspectedLocations,
              mapController: mapController.mapController,
              selectedLocationId: appState.selectedSuspectedLocation?.ticketNo,
              onLocationTap: onSuspectedLocationTap, // Keep the original callback
              shouldDimAll: shouldDisableNodeTaps,
              enabled: !shouldDisableNodeTaps, // Use enabled parameter instead
            ),
          );
        }

        // Build RF detection markers
        final rfDetectionMarkers = <Marker>[];
        if (rfDetections != null && rfDetections.isNotEmpty) {
          rfDetectionMarkers.addAll(
            RfDetectionMarkersBuilder.buildRfDetectionMarkers(
              detections: rfDetections,
              mapController: mapController.mapController,
              onDetectionTap: onRfDetectionTap,
              shouldDimAll: shouldDisableNodeTaps,
              enabled: !shouldDisableNodeTaps,
            ),
          );
        }

        // Build center marker for add/edit sessions
        final centerMarkers = _buildSessionMarkers(
          mapController: mapController,
          session: session,
          editSession: editSession,
        );

        // Build provisional pin for navigation/search mode
        final navigationMarkers = _buildNavigationMarkers(appState);

        // Build start/end pins for route visualization
        final routeMarkers = _buildRouteMarkers(appState);

        return MarkerLayer(
          markers: [
            ...rfDetectionMarkers,
            ...suspectedLocationMarkers,
            ...markers,
            ...centerMarkers,
            ...navigationMarkers,
            ...routeMarkers,
          ]
        );
      },
    );
  }

  /// Build center markers for add/edit sessions
  static List<Marker> _buildSessionMarkers({
    required AnimatedMapController mapController,
    required AddNodeSession? session,
    required EditNodeSession? editSession,
  }) {
    final centerMarkers = <Marker>[];
    if (session != null || editSession != null) {
      try {
        final center = mapController.mapController.camera.center;
        centerMarkers.add(
          Marker(
            point: center,
            width: kNodeIconDiameter,
            height: kNodeIconDiameter,
            child: CameraIcon(
              type: editSession != null ? CameraIconType.editing : CameraIconType.mock,
            ),
          ),
        );
      } catch (_) {
        // Controller not ready yet
      }
    }
    return centerMarkers;
  }

  /// Build provisional pin for navigation/search mode
  static List<Marker> _buildNavigationMarkers(AppState appState) {
    final markers = <Marker>[];
    if (appState.showProvisionalPin && appState.provisionalPinLocation != null) {
      markers.add(
        Marker(
          point: appState.provisionalPinLocation!,
          width: 32.0,
          height: 32.0,
          child: const ProvisionalPin(),
        ),
      );
    }
    return markers;
  }

  /// Build start/end pins for route visualization
  static List<Marker> _buildRouteMarkers(AppState appState) {
    final markers = <Marker>[];
    if (appState.showingOverview || appState.isInRouteMode || appState.isSettingSecondPoint) {
      if (appState.routeStart != null) {
        markers.add(
          Marker(
            point: appState.routeStart!,
            width: 32.0,
            height: 32.0,
            child: const LocationPin(type: PinType.start),
          ),
        );
      }
      if (appState.routeEnd != null) {
        markers.add(
          Marker(
            point: appState.routeEnd!,
            width: 32.0,
            height: 32.0,
            child: const LocationPin(type: PinType.end),
          ),
        );
      }
    }
    return markers;
  }

  /// Filter suspected locations that are too close to real nodes
  static List<SuspectedLocation> _filterSuspectedLocationsByProximity({
    required List<SuspectedLocation> suspectedLocations,
    required List<OsmNode> realNodes,
    required int minDistance, // in meters
  }) {
    if (minDistance <= 0) return suspectedLocations;
    
    const distance = Distance();
    final filteredLocations = <SuspectedLocation>[];
    
    for (final suspected in suspectedLocations) {
      bool tooClose = false;
      
      for (final realNode in realNodes) {
        final distanceMeters = distance.as(
          LengthUnit.Meter,
          suspected.centroid,
          realNode.coord,
        );
        
        if (distanceMeters < minDistance) {
          tooClose = true;
          break;
        }
      }
      
      if (!tooClose) {
        filteredLocations.add(suspected);
      }
    }
    
    return filteredLocations;
  }
}
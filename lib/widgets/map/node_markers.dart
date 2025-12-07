import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../models/osm_node.dart';
import '../node_tag_sheet.dart';
import '../camera_icon.dart';

/// Smart marker widget for surveillance node with single/double tap distinction
class NodeMapMarker extends StatefulWidget {
  final OsmNode node;
  final MapController mapController;
  final void Function(OsmNode)? onNodeTap;
  final bool enabled;
  
  const NodeMapMarker({
    required this.node, 
    required this.mapController, 
    this.onNodeTap,
    this.enabled = true,
    Key? key,
  }) : super(key: key);

  @override
  State<NodeMapMarker> createState() => _NodeMapMarkerState();
}

class _NodeMapMarkerState extends State<NodeMapMarker> {
  Timer? _tapTimer;
  // From dev_config.dart for build-time parameters
  static const Duration tapTimeout = kMarkerTapTimeout;

  void _onTap() {
    if (!widget.enabled) return; // Don't respond to taps when disabled
    
    _tapTimer = Timer(tapTimeout, () {
      // Don't center immediately - let the sheet opening handle the coordinated animation
      
      // Use callback if provided, otherwise fallback to direct modal
      if (widget.onNodeTap != null) {
        widget.onNodeTap!(widget.node);
      } else {
        // Fallback: This should not happen if callbacks are properly provided,
        // but if it does, at least open the sheet (without map coordination)
        debugPrint('[NodeMapMarker] Warning: onNodeTap callback not provided, using fallback');
        showModalBottomSheet(
          context: context,
          builder: (_) => NodeTagSheet(node: widget.node),
          showDragHandle: true,
        );
      }
    });
  }

  void _onDoubleTap() {
    if (!widget.enabled) return; // Don't respond to double taps when disabled
    
    _tapTimer?.cancel();
    widget.mapController.move(widget.node.coord, widget.mapController.camera.zoom + kNodeDoubleTapZoomDelta);
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check node state
    final isPendingUpload = widget.node.tags.containsKey('_pending_upload') && 
                           widget.node.tags['_pending_upload'] == 'true';
    final isPendingEdit = widget.node.tags.containsKey('_pending_edit') && 
                         widget.node.tags['_pending_edit'] == 'true';
    final isPendingDeletion = widget.node.tags.containsKey('_pending_deletion') && 
                             widget.node.tags['_pending_deletion'] == 'true';
    
    CameraIconType iconType;
    if (isPendingDeletion) {
      iconType = CameraIconType.pendingDeletion;
    } else if (isPendingUpload) {
      iconType = CameraIconType.pending;
    } else if (isPendingEdit) {
      iconType = CameraIconType.pendingEdit;
    } else {
      iconType = CameraIconType.real;
    }
    
    return GestureDetector(
      onTap: _onTap,
      onDoubleTap: _onDoubleTap,
      child: CameraIcon(type: iconType),
    );
  }
}

/// Helper class to build marker layers for surveillance nodes and user location
class NodeMarkersBuilder {
  static List<Marker> buildNodeMarkers({
    required List<OsmNode> nodes,
    required MapController mapController,
    LatLng? userLocation,
    int? selectedNodeId,
    void Function(OsmNode)? onNodeTap,
    bool shouldDim = false,
    bool enabled = true,
  }) {
    final markers = <Marker>[
      // Node markers
      ...nodes
        .where(_isValidNodeCoordinate)
        .map((n) {
          // Check if this node should be highlighted (selected) or dimmed
          final isSelected = selectedNodeId == n.id;
          final shouldDimNode = shouldDim || (selectedNodeId != null && !isSelected);
          
          return Marker(
            point: n.coord,
            width: kNodeIconDiameter,
            height: kNodeIconDiameter,
            child: Opacity(
              opacity: shouldDimNode ? 0.5 : 1.0,
              child: NodeMapMarker(
                node: n, 
                mapController: mapController,
                onNodeTap: onNodeTap,
                enabled: enabled,
              ),
            ),
          );
        }),
      
      // User location marker
      if (userLocation != null)
        Marker(
          point: userLocation,
          width: 16,
          height: 16,
          child: const Icon(Icons.my_location, color: Colors.blue),
        ),
    ];

    return markers;
  }

  static bool _isValidNodeCoordinate(OsmNode node) {
    return (node.coord.latitude != 0 || node.coord.longitude != 0) &&
           node.coord.latitude.abs() <= 90 && 
           node.coord.longitude.abs() <= 180;
  }
}
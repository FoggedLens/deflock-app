import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../models/osm_node.dart';
import '../node_tag_sheet.dart';
import '../camera_icon.dart';

/// Smart marker widget for camera with single/double tap distinction
class CameraMapMarker extends StatefulWidget {
  final OsmNode node;
  final MapController mapController;
  final void Function(OsmNode)? onNodeTap;
  
  const CameraMapMarker({
    required this.node, 
    required this.mapController, 
    this.onNodeTap,
    Key? key,
  }) : super(key: key);

  @override
  State<CameraMapMarker> createState() => _CameraMapMarkerState();
}

class _CameraMapMarkerState extends State<CameraMapMarker> {
  Timer? _tapTimer;
  // From dev_config.dart for build-time parameters
  static const Duration tapTimeout = kMarkerTapTimeout;

  void _onTap() {
    _tapTimer = Timer(tapTimeout, () {
      // Center on the node when opening the tag sheet
      // This prevents jumping when transitioning to edit mode
      widget.mapController.move(widget.node.coord, widget.mapController.camera.zoom);
      
      // Use callback if provided, otherwise fallback to direct modal
      if (widget.onNodeTap != null) {
        widget.onNodeTap!(widget.node);
      } else {
        showModalBottomSheet(
          context: context,
          builder: (_) => NodeTagSheet(node: widget.node),
          showDragHandle: true,
        );
      }
    });
  }

  void _onDoubleTap() {
    _tapTimer?.cancel();
    widget.mapController.move(widget.node.coord, widget.mapController.camera.zoom + 1);
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check camera state
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

/// Helper class to build marker layers for cameras and user location
class CameraMarkersBuilder {
  static List<Marker> buildCameraMarkers({
    required List<OsmNode> cameras,
    required MapController mapController,
    LatLng? userLocation,
    int? selectedNodeId,
    void Function(OsmNode)? onNodeTap,
  }) {
    final markers = <Marker>[
      // Camera markers
      ...cameras
        .where(_isValidCameraCoordinate)
        .map((n) {
          // Check if this node should be highlighted (selected) or dimmed
          final isSelected = selectedNodeId == n.id;
          final shouldDim = selectedNodeId != null && !isSelected;
          
          return Marker(
            point: n.coord,
            width: kCameraIconDiameter,
            height: kCameraIconDiameter,
            child: Opacity(
              opacity: shouldDim ? 0.5 : 1.0,
              child: CameraMapMarker(
                node: n, 
                mapController: mapController,
                onNodeTap: onNodeTap,
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

  static bool _isValidCameraCoordinate(OsmNode node) {
    return (node.coord.latitude != 0 || node.coord.longitude != 0) &&
           node.coord.latitude.abs() <= 90 && 
           node.coord.longitude.abs() <= 180;
  }
}
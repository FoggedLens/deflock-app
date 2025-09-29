import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../models/osm_camera_node.dart';
import '../node_tag_sheet.dart';
import '../camera_icon.dart';

/// Smart marker widget for camera with single/double tap distinction
class CameraMapMarker extends StatefulWidget {
  final OsmCameraNode node;
  final MapController mapController;
  const CameraMapMarker({required this.node, required this.mapController, Key? key}) : super(key: key);

  @override
  State<CameraMapMarker> createState() => _CameraMapMarkerState();
}

class _CameraMapMarkerState extends State<CameraMapMarker> {
  Timer? _tapTimer;
  // From dev_config.dart for build-time parameters
  static const Duration tapTimeout = kMarkerTapTimeout;

  void _onTap() {
    _tapTimer = Timer(tapTimeout, () {
      showModalBottomSheet(
        context: context,
        builder: (_) => NodeTagSheet(node: widget.node),
        showDragHandle: true,
      );
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
    required List<OsmCameraNode> cameras,
    required MapController mapController,
    LatLng? userLocation,
  }) {
    final markers = <Marker>[
      // Camera markers
      ...cameras
        .where(_isValidCameraCoordinate)
        .map((n) => Marker(
          point: n.coord,
          width: kCameraIconDiameter,
          height: kCameraIconDiameter,
          child: CameraMapMarker(node: n, mapController: mapController),
        )),
      
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

  static bool _isValidCameraCoordinate(OsmCameraNode node) {
    return (node.coord.latitude != 0 || node.coord.longitude != 0) &&
           node.coord.latitude.abs() <= 90 && 
           node.coord.longitude.abs() <= 180;
  }
}
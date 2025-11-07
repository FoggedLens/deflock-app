import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../dev_config.dart';
import '../../models/suspected_location.dart';
import '../suspected_location_sheet.dart';
import '../suspected_location_icon.dart';

/// Smart marker widget for suspected location with single/double tap distinction
class SuspectedLocationMapMarker extends StatefulWidget {
  final SuspectedLocation location;
  final MapController mapController;
  final void Function(SuspectedLocation)? onLocationTap;
  
  const SuspectedLocationMapMarker({
    required this.location, 
    required this.mapController, 
    this.onLocationTap,
    Key? key,
  }) : super(key: key);

  @override
  State<SuspectedLocationMapMarker> createState() => _SuspectedLocationMapMarkerState();
}

class _SuspectedLocationMapMarkerState extends State<SuspectedLocationMapMarker> {
  Timer? _tapTimer;
  // From dev_config.dart for build-time parameters
  static const Duration tapTimeout = kMarkerTapTimeout;

  void _onTap() {
    _tapTimer = Timer(tapTimeout, () {
      // Use callback if provided, otherwise fallback to direct modal
      if (widget.onLocationTap != null) {
        widget.onLocationTap!(widget.location);
      } else {
        showModalBottomSheet(
          context: context,
          builder: (_) => SuspectedLocationSheet(location: widget.location),
          showDragHandle: true,
        );
      }
    });
  }

  void _onDoubleTap() {
    _tapTimer?.cancel();
    widget.mapController.move(widget.location.centroid, widget.mapController.camera.zoom + kNodeDoubleTapZoomDelta);
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onDoubleTap: _onDoubleTap,
      child: const SuspectedLocationIcon(),
    );
  }
}

/// Helper class to build marker layers for suspected locations
class SuspectedLocationMarkersBuilder {
  static List<Marker> buildSuspectedLocationMarkers({
    required List<SuspectedLocation> locations,
    required MapController mapController,
    String? selectedLocationId,
    void Function(SuspectedLocation)? onLocationTap,
  }) {
    final markers = <Marker>[];
    
    for (final location in locations) {
      if (!_isValidCoordinate(location.centroid)) continue;
      
      // Check if this location should be highlighted (selected) or dimmed
      final isSelected = selectedLocationId == location.ticketNo;
      final shouldDim = selectedLocationId != null && !isSelected;
      
      markers.add(
        Marker(
          point: location.centroid,
          width: 20,
          height: 20,
          child: Opacity(
            opacity: shouldDim ? 0.5 : 1.0,
            child: SuspectedLocationMapMarker(
              location: location, 
              mapController: mapController,
              onLocationTap: onLocationTap,
            ),
          ),
        ),
      );
    }

    return markers;
  }

  static bool _isValidCoordinate(LatLng coord) {
    return (coord.latitude != 0 || coord.longitude != 0) &&
           coord.latitude.abs() <= 90 && 
           coord.longitude.abs() <= 180;
  }
}
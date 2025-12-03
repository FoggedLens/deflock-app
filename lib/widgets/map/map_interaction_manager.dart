import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../state/session_state.dart';
import '../../dev_config.dart';

/// Manages map interaction options and gesture handling logic.
/// Handles constrained node interactions, zoom restrictions, and gesture configuration.
class MapInteractionManager {
  
  /// Get interaction options for the map based on whether we're editing a constrained node.
  /// Allows zoom and rotation but disables all forms of panning for constrained nodes unless extract is enabled.
  InteractionOptions getInteractionOptions(EditNodeSession? editSession) {
    // Check if we're editing a constrained node that's not being extracted
    if (editSession?.originalNode.isConstrained == true && editSession?.extractFromWay != true) {
      // Constrained node (not extracting): only allow pinch zoom and rotation, disable ALL panning
      return const InteractionOptions(
        enableMultiFingerGestureRace: true,
        flags: InteractiveFlag.pinchZoom | InteractiveFlag.rotate,
        scrollWheelVelocity: kScrollWheelVelocity,
        pinchZoomThreshold: kPinchZoomThreshold,
        pinchMoveThreshold: kPinchMoveThreshold,
      );
    }
    
    // Normal case: all interactions allowed with gesture race to prevent accidental rotation during zoom
    return const InteractionOptions(
      enableMultiFingerGestureRace: true,
      flags: InteractiveFlag.doubleTapDragZoom |
          InteractiveFlag.doubleTapZoom |
          InteractiveFlag.drag |
          InteractiveFlag.flingAnimation |
          InteractiveFlag.pinchZoom |
          InteractiveFlag.rotate |
          InteractiveFlag.scrollWheelZoom,
      scrollWheelVelocity: kScrollWheelVelocity,
      pinchZoomThreshold: kPinchZoomThreshold,
      pinchMoveThreshold: kPinchMoveThreshold,
    );
  }

  /// Check if the map has moved significantly enough to cancel stale tile requests.
  /// Uses a simple distance threshold - roughly equivalent to 1/4 screen width at zoom 15.
  bool mapMovedSignificantly(LatLng? newCenter, LatLng? oldCenter) {
    if (newCenter == null || oldCenter == null) return false;
    
    // Calculate approximate distance in meters (rough calculation for performance)
    final latDiff = (newCenter.latitude - oldCenter.latitude).abs();
    final lngDiff = (newCenter.longitude - oldCenter.longitude).abs();
    
    // Threshold: ~500 meters (roughly 1/4 screen at zoom 15)
    // This prevents excessive cancellations on small movements while catching real pans
    const double significantMovementThreshold = 0.005; // degrees (~500m at equator)
    
    return latDiff > significantMovementThreshold || lngDiff > significantMovementThreshold;
  }
}
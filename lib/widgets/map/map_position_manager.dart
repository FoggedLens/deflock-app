import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Manages map position persistence and initial positioning.
/// Handles saving/loading last map position and moving to initial locations.
class MapPositionManager {
  LatLng? _initialLocation;
  double? _initialZoom;
  bool _hasMovedToInitialLocation = false;

  /// Get the initial location (if any was loaded)
  LatLng? get initialLocation => _initialLocation;
  
  /// Get the initial zoom (if any was loaded)
  double? get initialZoom => _initialZoom;
  
  /// Whether we've already moved to the initial location
  bool get hasMovedToInitialLocation => _hasMovedToInitialLocation;

  /// Load the last map position from persistent storage.
  /// Call this during initialization to set up initial location.
  Future<void> loadLastMapPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('last_map_latitude');
      final lng = prefs.getDouble('last_map_longitude');
      final zoom = prefs.getDouble('last_map_zoom');
      
      if (lat != null && lng != null && 
          _isValidCoordinate(lat) && _isValidCoordinate(lng)) {
        final validZoom = zoom != null && _isValidZoom(zoom) ? zoom : 15.0;
        _initialLocation = LatLng(lat, lng);
        _initialZoom = validZoom;
        debugPrint('[MapPositionManager] Loaded last map position: ${_initialLocation!.latitude}, ${_initialLocation!.longitude}, zoom: $_initialZoom');
      } else {
        debugPrint('[MapPositionManager] Invalid saved coordinates, using defaults');
      }
    } catch (e) {
      debugPrint('[MapPositionManager] Failed to load last map position: $e');
    }
  }

  /// Move to initial location if we have one and haven't moved yet.
  /// Call this after the map controller is ready.
  void moveToInitialLocationIfNeeded(AnimatedMapController controller) {
    if (!_hasMovedToInitialLocation && _initialLocation != null) {
      try {
        final zoom = _initialZoom ?? 15.0;
        // Double-check coordinates are valid before moving
        if (_isValidCoordinate(_initialLocation!.latitude) && 
            _isValidCoordinate(_initialLocation!.longitude) && 
            _isValidZoom(zoom)) {
          controller.mapController.move(_initialLocation!, zoom);
          _hasMovedToInitialLocation = true;
          debugPrint('[MapPositionManager] Moved to initial location: ${_initialLocation!.latitude}, ${_initialLocation!.longitude}');
        } else {
          debugPrint('[MapPositionManager] Invalid initial location, not moving: ${_initialLocation!.latitude}, ${_initialLocation!.longitude}, zoom: $zoom');
        }
      } catch (e) {
        debugPrint('[MapPositionManager] Failed to move to initial location: $e');
      }
    }
  }

  /// Save the current map position to persistent storage.
  /// Call this when the map position changes.
  Future<void> saveMapPosition(LatLng location, double zoom) async {
    try {
      // Validate coordinates and zoom before saving
      if (!_isValidCoordinate(location.latitude) || 
          !_isValidCoordinate(location.longitude) || 
          !_isValidZoom(zoom)) {
        debugPrint('[MapPositionManager] Invalid map position, not saving: lat=${location.latitude}, lng=${location.longitude}, zoom=$zoom');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_map_latitude', location.latitude);
      await prefs.setDouble('last_map_longitude', location.longitude);
      await prefs.setDouble('last_map_zoom', zoom);
      debugPrint('[MapPositionManager] Saved last map position: ${location.latitude}, ${location.longitude}, zoom: $zoom');
    } catch (e) {
      debugPrint('[MapPositionManager] Failed to save last map position: $e');
    }
  }



  /// Clear any stored map position (useful for recovery from invalid data)
  static Future<void> clearStoredMapPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_map_latitude');
      await prefs.remove('last_map_longitude');
      await prefs.remove('last_map_zoom');
      debugPrint('[MapPositionManager] Cleared stored map position');
    } catch (e) {
      debugPrint('[MapPositionManager] Failed to clear stored map position: $e');
    }
  }

  /// Validate that a coordinate value is valid (not NaN, not infinite, within bounds)
  bool _isValidCoordinate(double value) {
    return !value.isNaN && 
           !value.isInfinite && 
           value >= -180.0 && 
           value <= 180.0;
  }

  /// Validate that a zoom level is valid
  bool _isValidZoom(double zoom) {
    return !zoom.isNaN && 
           !zoom.isInfinite && 
           zoom >= 1.0 && 
           zoom <= 25.0;
  }
}
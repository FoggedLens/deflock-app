import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

import '../services/map_data_provider.dart';
import '../services/camera_cache.dart';
import '../models/camera_profile.dart';
import '../models/osm_camera_node.dart';
import '../app_state.dart';

/// Provides cameras for a map view, using an in-memory cache and optionally
/// merging in new results from Overpass via MapDataProvider when not offline.
class CameraProviderWithCache extends ChangeNotifier {
  static final CameraProviderWithCache instance = CameraProviderWithCache._internal();
  factory CameraProviderWithCache() => instance;
  CameraProviderWithCache._internal();

  Timer? _debounceTimer;

  /// Call this to get (quickly) all cached overlays for the given view.
  /// Filters by currently enabled profiles.
  List<OsmCameraNode> getCachedCamerasForBounds(LatLngBounds bounds) {
    final allCameras = CameraCache.instance.queryByBounds(bounds);
    final enabledProfiles = AppState.instance.enabledProfiles;
    
    // If no profiles are enabled, show no cameras
    if (enabledProfiles.isEmpty) return [];
    
    // Filter cameras to only show those matching enabled profiles
    return allCameras.where((camera) {
      return _matchesAnyProfile(camera, enabledProfiles);
    }).toList();
  }

  /// Call this when the map view changes (bounds/profiles), triggers async fetch
  /// and notifies listeners/UI when new data is available.
  void fetchAndUpdate({
    required LatLngBounds bounds,
    required List<CameraProfile> profiles,
    UploadMode uploadMode = UploadMode.production,
  }) {
    // Fast: serve cached immediately
    notifyListeners();
    // Debounce rapid panning/zooming
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      try {
        // Use MapSource.auto to handle both offline and online modes appropriately
        final fresh = await MapDataProvider().getCameras(
          bounds: bounds,
          profiles: profiles,
          uploadMode: uploadMode,
          source: MapSource.auto,
        );
        if (fresh.isNotEmpty) {
          CameraCache.instance.addOrUpdate(fresh);
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[CameraProviderWithCache] Camera fetch failed: $e');
        // Cache already holds whatever is available for the view
      }
    });
  }

  /// Optionally: clear the cache (could be used for testing/dev)
  void clearCache() {
    CameraCache.instance.clear();
    notifyListeners();
  }

  /// Force refresh the display (useful when filters change but cache doesn't)
  void refreshDisplay() {
    notifyListeners();
  }

  /// Check if a camera matches any of the provided profiles
  bool _matchesAnyProfile(OsmCameraNode camera, List<CameraProfile> profiles) {
    for (final profile in profiles) {
      if (_cameraMatchesProfile(camera, profile)) return true;
    }
    return false;
  }

  /// Check if a camera matches a specific profile (all profile tags must match)
  bool _cameraMatchesProfile(OsmCameraNode camera, CameraProfile profile) {
    for (final entry in profile.tags.entries) {
      if (camera.tags[entry.key] != entry.value) return false;
    }
    return true;
  }
}

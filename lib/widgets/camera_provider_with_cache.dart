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
  List<OsmCameraNode> getCachedCamerasForBounds(LatLngBounds bounds) {
    return CameraCache.instance.queryByBounds(bounds);
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
      final isOffline = AppState.instance.offlineMode;
      if (!isOffline) {
        try {
          final fresh = await MapDataProvider().getCameras(
            bounds: bounds,
            profiles: profiles,
            uploadMode: uploadMode,
            source: MapSource.remote,
          );
          if (fresh.isNotEmpty) {
            CameraCache.instance.addOrUpdate(fresh);
            notifyListeners();
          }
        } catch (e) {
          debugPrint('[CameraProviderWithCache] Overpass fetch failed: $e');
          // Cache already holds whatever is available for the view
        }
      } // else, only cache is used
    });
  }

  /// Optionally: clear the cache (could be used for testing/dev)
  void clearCache() {
    CameraCache.instance.clear();
    notifyListeners();
  }
}

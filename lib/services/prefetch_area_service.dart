import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/node_profile.dart';
import '../models/osm_node.dart';
import '../app_state.dart';
import '../dev_config.dart';
import 'map_data_submodules/nodes_from_overpass.dart';
import 'node_cache.dart';
import 'network_status.dart';
import '../widgets/camera_provider_with_cache.dart';

/// Manages pre-fetching larger areas to reduce Overpass API calls.
/// Uses zoom level 10 areas and automatically splits if hitting node limits.
class PrefetchAreaService {
  static final PrefetchAreaService _instance = PrefetchAreaService._();
  factory PrefetchAreaService() => _instance;
  PrefetchAreaService._();

  // Current pre-fetched area and associated data
  LatLngBounds? _preFetchedArea;
  List<NodeProfile>? _preFetchedProfiles;
  UploadMode? _preFetchedUploadMode;
  DateTime? _lastFetchTime;
  bool _preFetchInProgress = false;
  
  // Debounce timer to avoid rapid requests while user is panning
  Timer? _debounceTimer;
  
  // Configuration from dev_config
  static final double _areaExpansionMultiplier = dev.dev.kPreFetchAreaExpansionMultiplier;
  static final int _preFetchZoomLevel = dev.dev.kPreFetchZoomLevel;
  
  /// Check if the given bounds are fully within the current pre-fetched area.
  bool isWithinPreFetchedArea(LatLngBounds bounds, List<NodeProfile> profiles, UploadMode uploadMode) {
    if (_preFetchedArea == null || _preFetchedProfiles == null || _preFetchedUploadMode == null) {
      return false;
    }
    
    // Check if profiles and upload mode match
    if (_preFetchedUploadMode != uploadMode) {
      return false;
    }
    
    if (!_profileListsEqual(_preFetchedProfiles!, profiles)) {
      return false;
    }
    
    // Check if bounds are fully contained within pre-fetched area
    return bounds.north <= _preFetchedArea!.north &&
           bounds.south >= _preFetchedArea!.south &&
           bounds.east <= _preFetchedArea!.east &&
           bounds.west >= _preFetchedArea!.west;
  }
  
  /// Check if cached data is stale (older than configured refresh interval).
  bool isDataStale() {
    if (_lastFetchTime == null) return true;
    return DateTime.now().difference(_lastFetchTime!).inSeconds > dev.kDataRefreshIntervalSeconds;
  }
  
  /// Request pre-fetch for the given view bounds if not already covered or if data is stale.
  /// Uses debouncing to avoid rapid requests while user is panning.
  void requestPreFetchIfNeeded({
    required LatLngBounds viewBounds,
    required List<NodeProfile> profiles,
    required UploadMode uploadMode,
  }) {
    // Skip if already in progress
    if (_preFetchInProgress) {
      debugPrint('[PrefetchAreaService] Pre-fetch already in progress, skipping');
      return;
    }
    
    // Check both spatial and temporal conditions
    final isWithinArea = isWithinPreFetchedArea(viewBounds, profiles, uploadMode);
    final isStale = isDataStale();
    
    if (isWithinArea && !isStale) {
      debugPrint('[PrefetchAreaService] Current view within fresh pre-fetched area, no fetch needed');
      return;
    }
    
    if (isStale) {
      debugPrint('[PrefetchAreaService] Data is stale (>${dev.kDataRefreshIntervalSeconds}s), refreshing');
    } else {
      debugPrint('[PrefetchAreaService] Current view outside pre-fetched area, fetching larger area');
    }
    
    // Cancel any pending debounced request
    _debounceTimer?.cancel();
    
    // Debounce to avoid rapid requests while user is still moving
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      _startPreFetch(
        viewBounds: viewBounds,
        profiles: profiles,
        uploadMode: uploadMode,
      );
    });
  }
  
  /// Start the actual pre-fetch operation.
  Future<void> _startPreFetch({
    required LatLngBounds viewBounds,
    required List<NodeProfile> profiles,
    required UploadMode uploadMode,
  }) async {
    if (_preFetchInProgress) return;
    
    _preFetchInProgress = true;
    
    try {
      // Calculate expanded area for pre-fetching
      final preFetchArea = _expandBounds(viewBounds, _areaExpansionMultiplier);
      
      debugPrint('[PrefetchAreaService] Starting pre-fetch for area: ${preFetchArea.south},${preFetchArea.west} to ${preFetchArea.north},${preFetchArea.east}');
      
      // Fetch nodes for the expanded area (unlimited - let splitting handle 50k limit)
      final nodes = await fetchOverpassNodes(
        bounds: preFetchArea,
        profiles: profiles,
        uploadMode: uploadMode,
        maxResults: 0, // Unlimited - our splitting system handles the 50k limit gracefully
      );
      
      debugPrint('[PrefetchAreaService] Pre-fetch completed: ${nodes.length} nodes retrieved');
      
      // Update cache with new nodes (fresh data overwrites stale, but preserves underscore tags)
      if (nodes.isNotEmpty) {
        NodeCache.instance.addOrUpdate(nodes);
      }
      
      // Store the pre-fetched area info and timestamp
      _preFetchedArea = preFetchArea;
      _preFetchedProfiles = List.from(profiles);
      _preFetchedUploadMode = uploadMode;
      _lastFetchTime = DateTime.now();
      
      // Report completion to network status (only if user was waiting)
      NetworkStatus.instance.setSuccess();
      
      // Notify UI that cache has been updated with fresh data
      CameraProviderWithCache.instance.refreshDisplay();
      
    } catch (e) {
      debugPrint('[PrefetchAreaService] Pre-fetch failed: $e');
      // Report failure to network status (only if user was waiting)
      if (e.toString().contains('timeout') || e.toString().contains('timed out')) {
        NetworkStatus.instance.setTimeoutError();
      } else {
        NetworkStatus.instance.setNetworkError();
      }
      // Don't update pre-fetched area info on failure
    } finally {
      _preFetchInProgress = false;
    }
  }
  
  /// Expand bounds by the given multiplier, maintaining center point.
  LatLngBounds _expandBounds(LatLngBounds bounds, double multiplier) {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;
    
    final latSpan = (bounds.north - bounds.south) * multiplier / 2;
    final lngSpan = (bounds.east - bounds.west) * multiplier / 2;
    
    return LatLngBounds(
      LatLng(centerLat - latSpan, centerLng - lngSpan), // Southwest
      LatLng(centerLat + latSpan, centerLng + lngSpan), // Northeast
    );
  }
  
  /// Check if two profile lists are equal by comparing IDs.
  bool _profileListsEqual(List<NodeProfile> list1, List<NodeProfile> list2) {
    if (list1.length != list2.length) return false;
    final ids1 = list1.map((p) => p.id).toSet();
    final ids2 = list2.map((p) => p.id).toSet();
    return ids1.length == ids2.length && ids1.containsAll(ids2);
  }
  
  /// Clear the pre-fetched area (e.g., when profiles change significantly).
  void clearPreFetchedArea() {
    _preFetchedArea = null;
    _preFetchedProfiles = null;
    _preFetchedUploadMode = null;
    _lastFetchTime = null;
    debugPrint('[PrefetchAreaService] Pre-fetched area cleared');
  }
  
  /// Dispose of resources.
  void dispose() {
    _debounceTimer?.cancel();
  }
}
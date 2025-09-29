import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/offline_area_service.dart';
import '../services/network_status.dart';
import '../models/osm_camera_node.dart';
import '../models/node_profile.dart';
import '../models/tile_provider.dart';
import 'debouncer.dart';
import 'camera_provider_with_cache.dart';
import 'camera_icon.dart';
import 'map/camera_markers.dart';
import 'map/direction_cones.dart';
import 'map/map_overlays.dart';
import 'map/map_position_manager.dart';
import 'map/tile_layer_manager.dart';
import 'map/camera_refresh_controller.dart';
import 'map/gps_controller.dart';
import 'network_status_indicator.dart';
import '../dev_config.dart';
import '../app_state.dart' show FollowMeMode;

class MapView extends StatefulWidget {
  final AnimatedMapController controller;
  const MapView({
    super.key,
    required this.controller,
    required this.followMeMode,
    required this.onUserGesture,
    this.bottomPadding = 0.0,
  });

  final FollowMeMode followMeMode;
  final VoidCallback onUserGesture;
  final double bottomPadding;

  @override
  State<MapView> createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  late final AnimatedMapController _controller;
  final Debouncer _cameraDebounce = Debouncer(kDebounceCameraRefresh);
  final Debouncer _tileDebounce = Debouncer(const Duration(milliseconds: 150));
  final Debouncer _mapPositionDebounce = Debouncer(const Duration(milliseconds: 1000));

  late final MapPositionManager _positionManager;
  late final TileLayerManager _tileManager;
  late final CameraRefreshController _cameraController;
  late final GpsController _gpsController;
  
  // Track zoom to clear queue on zoom changes
  double? _lastZoom;

  @override
  void initState() {
    super.initState();
    OfflineAreaService();
    _controller = widget.controller;
    _positionManager = MapPositionManager();
    _tileManager = TileLayerManager();
    _tileManager.initialize();
    _cameraController = CameraRefreshController();
    _cameraController.initialize(onCamerasUpdated: _onCamerasUpdated);
    _gpsController = GpsController();
    
    // Load last map position before initializing GPS
    _positionManager.loadLastMapPosition().then((_) {
      // Move to last known position after loading and widget is built
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _positionManager.moveToInitialLocationIfNeeded(_controller);
      });
    });
    
    // Initialize GPS with callback for position updates and follow-me
    _gpsController.initializeWithCallback(
      followMeMode: widget.followMeMode,
      controller: _controller,
      onLocationUpdated: () => setState(() {}),
      getCurrentFollowMeMode: () {
        // Use mounted check to avoid calling context when widget is disposed
        if (mounted) {
          try {
            return context.read<AppState>().followMeMode;
          } catch (e) {
            debugPrint('[MapView] Could not read AppState, defaulting to off: $e');
            return FollowMeMode.off;
          }
        }
        return FollowMeMode.off;
      },
    );

    // Fetch initial cameras
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCamerasFromProvider();
    });
  }





  @override
  void dispose() {
    _cameraDebounce.dispose();
    _tileDebounce.dispose();
    _mapPositionDebounce.dispose();
    _cameraController.dispose();
    _tileManager.dispose();
    _gpsController.dispose();
    super.dispose();
  }

  void _onCamerasUpdated() {
    if (mounted) setState(() {});
  }

  /// Public method to retry location initialization (e.g., after permission granted)
  void retryLocationInit() {
    _gpsController.retryLocationInit();
  }

  /// Expose static methods from MapPositionManager for external access
  static Future<void> clearStoredMapPosition() => 
      MapPositionManager.clearStoredMapPosition();



  void _refreshCamerasFromProvider() {
    final appState = context.read<AppState>();
    _cameraController.refreshCamerasFromProvider(
      controller: _controller,
      enabledProfiles: appState.enabledProfiles,
      uploadMode: appState.uploadMode,
      context: context,
    );
  }





  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle follow-me mode changes - only if it actually changed
    if (widget.followMeMode != oldWidget.followMeMode) {
      _gpsController.handleFollowMeModeChange(
        newMode: widget.followMeMode,
        oldMode: oldWidget.followMeMode,
        controller: _controller,
      );
    }
  }

  double _safeZoom() {
    try {
      return _controller.mapController.camera.zoom;
    } catch (_) {
      return 15.0;
    }
  }







  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.session;
    final editSession = appState.editSession;

    // Check if enabled profiles changed and refresh cameras if needed
    _cameraController.checkAndHandleProfileChanges(
      currentEnabledProfiles: appState.enabledProfiles,
      onProfilesChanged: _refreshCamerasFromProvider,
    );

    // Check if tile type OR offline mode changed and clear cache if needed
    final cacheCleared = _tileManager.checkAndClearCacheIfNeeded(
      currentTileTypeId: appState.selectedTileType?.id,
      currentOfflineMode: appState.offlineMode,
    );
    
    if (cacheCleared) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tileManager.clearTileQueue();
      });
    }

    // Seed add‑mode target once, after first controller center is available.
    if (session != null && session.target == null) {
      try {
        final center = _controller.mapController.camera.center;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => appState.updateSession(target: center),
        );
      } catch (_) {/* controller not ready yet */}
    }
    
    // For edit sessions, center the map on the camera being edited initially
    if (editSession != null && _controller.mapController.camera.center != editSession.target) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) {
          try {
            _controller.mapController.move(editSession.target, _controller.mapController.camera.zoom);
          } catch (_) {/* controller not ready yet */}
        },
      );
    }

    final zoom = _safeZoom();
    // Fetch cached cameras for current map bounds (using Consumer so overlays redraw instantly)
    Widget cameraLayers = Consumer<CameraProviderWithCache>(
      builder: (context, cameraProvider, child) {
        LatLngBounds? mapBounds;
        try {
          mapBounds = _controller.mapController.camera.visibleBounds;
        } catch (_) {
          mapBounds = null;
        }
        final cameras = (mapBounds != null)
            ? cameraProvider.getCachedNodesForBounds(mapBounds)
            : <OsmCameraNode>[];
        
        final markers = CameraMarkersBuilder.buildCameraMarkers(
          cameras: cameras,
          mapController: _controller.mapController,
          userLocation: _gpsController.currentLocation,
        );

        final overlays = DirectionConesBuilder.buildDirectionCones(
          cameras: cameras,
          zoom: zoom,
          session: session,
          editSession: editSession,
        );

        // Build edit lines connecting original cameras to their edited positions
        final editLines = _buildEditLines(cameras);

        // Build center marker for add/edit sessions
        final centerMarkers = <Marker>[];
        if (session != null || editSession != null) {
          try {
            final center = _controller.mapController.camera.center;
            centerMarkers.add(
              Marker(
                point: center,
                width: kCameraIconDiameter,
                height: kCameraIconDiameter,
                child: CameraIcon(
                  type: editSession != null ? CameraIconType.editing : CameraIconType.mock,
                ),
              ),
            );
          } catch (_) {
            // Controller not ready yet
          }
        }

        return Stack(
          children: [
            PolygonLayer(polygons: overlays),
            if (editLines.isNotEmpty) PolylineLayer(polylines: editLines),
            MarkerLayer(markers: [...markers, ...centerMarkers]),
          ],
        );
      }
    );

    return Stack(
      children: [
        AnimatedPadding(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: widget.bottomPadding),
          child: FlutterMap(
            key: ValueKey('map_${appState.offlineMode}_${appState.selectedTileType?.id ?? 'none'}_${_tileManager.mapRebuildKey}'),
            mapController: _controller.mapController,
            options: MapOptions(
              initialCenter: _gpsController.currentLocation ?? _positionManager.initialLocation ?? LatLng(37.7749, -122.4194),
            initialZoom: _positionManager.initialZoom ?? 15,
            maxZoom: 19,
            onPositionChanged: (pos, gesture) {
              setState(() {}); // Instant UI update for zoom, etc.
              if (gesture) widget.onUserGesture();
              if (session != null) {
                appState.updateSession(target: pos.center);
              }
              if (editSession != null) {
                appState.updateEditSession(target: pos.center);
              }
              
              // Start dual-source waiting when map moves (user is expecting new tiles AND nodes)
              NetworkStatus.instance.setDualSourceWaiting();
              
              // Only clear tile queue on significant ZOOM changes (not panning)
              final currentZoom = pos.zoom;
              final zoomChanged = _lastZoom != null && (currentZoom - _lastZoom!).abs() > 0.5;
              
              if (zoomChanged) {
                _tileDebounce(() {
                  // Clear stale tile requests on zoom change (quietly)
                  _tileManager.clearTileQueueImmediate();
                });
              }
              _lastZoom = currentZoom;
              
              // Save map position (debounced to avoid excessive writes)
              _mapPositionDebounce(() {
                _positionManager.saveMapPosition(pos.center, pos.zoom);
              });
              
              // Request more cameras on any map movement/zoom at valid zoom level (slower debounce)
              if (pos.zoom >= 10) {
                _cameraDebounce(_refreshCamerasFromProvider);
              } else {
                // Skip nodes at low zoom - report immediate completion (brutalist approach)
                NetworkStatus.instance.reportNodeComplete();
              }
            },
          ),
          children: [
            _tileManager.buildTileLayer(
              selectedProvider: appState.selectedTileProvider,
              selectedTileType: appState.selectedTileType,
            ),
            cameraLayers,
            // Built-in scale bar from flutter_map, positioned relative to button bar
            Scalebar(
              alignment: Alignment.bottomLeft,
              padding: EdgeInsets.only(
                left: 8, 
                bottom: bottomPositionFromButtonBar(kScaleBarSpacingAboveButtonBar, MediaQuery.of(context).padding.bottom)
              ),
              textStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              lineColor: Colors.black,
              strokeWidth: 3,
              // backgroundColor removed in flutter_map >=8 (wrap in Container if needed)
            ),
          ],
          ),
        ),

        // All map overlays (mode indicator, zoom, attribution, add pin)
        MapOverlays(
          mapController: _controller.mapController,
          uploadMode: appState.uploadMode,
          session: session,
          editSession: editSession,
          attribution: appState.selectedTileType?.attribution,
        ),

        // Network status indicator (top-left)
        const NetworkStatusIndicator(),
      ],
    );
  }

  /// Build polylines connecting original cameras to their edited positions
  List<Polyline> _buildEditLines(List<OsmCameraNode> cameras) {
    final lines = <Polyline>[];
    
    // Create a lookup map of original node IDs to their coordinates
    final originalNodes = <int, LatLng>{};
    for (final camera in cameras) {
      if (camera.tags['_pending_edit'] == 'true') {
        originalNodes[camera.id] = camera.coord;
      }
    }
    
    // Find edited cameras and draw lines to their originals
    for (final camera in cameras) {
      final originalIdStr = camera.tags['_original_node_id'];
      if (originalIdStr != null && camera.tags['_pending_upload'] == 'true') {
        final originalId = int.tryParse(originalIdStr);
        final originalCoord = originalId != null ? originalNodes[originalId] : null;
        
        if (originalCoord != null) {
          lines.add(Polyline(
            points: [originalCoord, camera.coord],
            color: kCameraRingColorPending,
            strokeWidth: 3.0,
          ));
        }
      }
    }
    
    return lines;
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/offline_area_service.dart';
import '../services/network_status.dart';
import '../models/osm_node.dart';
import '../models/node_profile.dart';
import '../models/suspected_location.dart';
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
import 'map/suspected_location_markers.dart';
import 'network_status_indicator.dart';
import 'provisional_pin.dart';
import 'proximity_alert_banner.dart';
import '../dev_config.dart';
import '../app_state.dart' show FollowMeMode;
import '../services/proximity_alert_service.dart';
import 'sheet_aware_map.dart';

class MapView extends StatefulWidget {
  final AnimatedMapController controller;
  const MapView({
    super.key,
    required this.controller,
    required this.followMeMode,
    required this.onUserGesture,
    this.sheetHeight = 0.0,
    this.selectedNodeId,
    this.onNodeTap,
    this.onSuspectedLocationTap,
    this.onSearchPressed,
  });

  final FollowMeMode followMeMode;
  final VoidCallback onUserGesture;
  final double sheetHeight;
  final int? selectedNodeId;
  final void Function(OsmNode)? onNodeTap;
  final void Function(SuspectedLocation)? onSuspectedLocationTap;
  final VoidCallback? onSearchPressed;

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
  
  // State for proximity alert banner
  bool _showProximityBanner = false;

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
    
    // Initialize proximity alert service
    ProximityAlertService().initialize(
      onVisualAlert: () {
        if (mounted) {
          setState(() {
            _showProximityBanner = true;
          });
        }
      },
    );
    
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
      getProximityAlertsEnabled: () {
        if (mounted) {
          try {
            return context.read<AppState>().proximityAlertsEnabled;
          } catch (e) {
            debugPrint('[MapView] Could not read proximity alerts enabled: $e');
            return false;
          }
        }
        return false;
      },
      getProximityAlertDistance: () {
        if (mounted) {
          try {
            return context.read<AppState>().proximityAlertDistance;
          } catch (e) {
            debugPrint('[MapView] Could not read proximity alert distance: $e');
            return 200;
          }
        }
        return 200;
      },
      getNearbyNodes: () {
        if (mounted) {
          try {
            final cameraProvider = context.read<CameraProviderWithCache>();
            LatLngBounds? mapBounds;
            try {
              mapBounds = _controller.mapController.camera.visibleBounds;
            } catch (_) {
              return [];
            }
            return mapBounds != null 
                ? cameraProvider.getCachedNodesForBounds(mapBounds)
                : [];
          } catch (e) {
            debugPrint('[MapView] Could not get nearby nodes: $e');
            return [];
          }
        }
        return [];
      },
      getEnabledProfiles: () {
        if (mounted) {
          try {
            return context.read<AppState>().enabledProfiles;
          } catch (e) {
            debugPrint('[MapView] Could not read enabled profiles: $e');
            return [];
          }
        }
        return [];
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
  
  /// Get current user location
  LatLng? getUserLocation() {
    return _gpsController.currentLocation;
  }

  /// Expose static methods from MapPositionManager for external access
  static Future<void> clearStoredMapPosition() => 
      MapPositionManager.clearStoredMapPosition();

  /// Get minimum zoom level for camera fetching based on upload mode
  int _getMinZoomForCameras(BuildContext context) {
    final appState = context.read<AppState>();
    final uploadMode = appState.uploadMode;
    
    // OSM API (sandbox mode) needs higher zoom level due to bbox size limits
    if (uploadMode == UploadMode.sandbox) {
      return kOsmApiMinZoomLevel;
    } else {
      return kNodeMinZoomLevel;
    }
  }

  /// Show zoom warning if user is below minimum zoom level
  void _showZoomWarningIfNeeded(BuildContext context, double currentZoom, int minZoom) {
    // Only show warning once per zoom level to avoid spam
    if (currentZoom.floor() == (minZoom - 1)) {
      final appState = context.read<AppState>();
      final uploadMode = appState.uploadMode;
      
      final message = uploadMode == UploadMode.sandbox 
          ? 'Zoom to level $minZoom or higher to see nodes in sandbox mode (OSM API bbox limit)'
          : 'Zoom to level $minZoom or higher to see surveillance nodes';
      
      // Show a brief snackbar
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }



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
    
    // Edit sessions don't need to center - we're already centered from the node tap
    // SheetAwareMap handles the visual positioning
    
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
            : <OsmNode>[];
        
        // Determine if we should dim camera markers (when suspected location is selected)
        final shouldDimCameras = appState.selectedSuspectedLocation != null;
        
        final markers = CameraMarkersBuilder.buildCameraMarkers(
          cameras: cameras,
          mapController: _controller.mapController,
          userLocation: _gpsController.currentLocation,
          selectedNodeId: widget.selectedNodeId,
          onNodeTap: widget.onNodeTap,
          shouldDim: shouldDimCameras,
        );

        // Build suspected location markers
        final suspectedLocationMarkers = <Marker>[];
        if (appState.suspectedLocationsEnabled && mapBounds != null) {
          final suspectedLocations = appState.getSuspectedLocationsInBounds(
            north: mapBounds.north,
            south: mapBounds.south,
            east: mapBounds.east,
            west: mapBounds.west,
          );
          
          suspectedLocationMarkers.addAll(
            SuspectedLocationMarkersBuilder.buildSuspectedLocationMarkers(
              locations: suspectedLocations,
              mapController: _controller.mapController,
              selectedLocationId: appState.selectedSuspectedLocation?.ticketNo,
              onLocationTap: widget.onSuspectedLocationTap,
            ),
          );
        }

        // Get current zoom level for direction cones
        double currentZoom = 15.0; // fallback
        try {
          currentZoom = _controller.mapController.camera.zoom;
        } catch (_) {
          // Controller not ready yet, use fallback
        }

        final overlays = DirectionConesBuilder.buildDirectionCones(
          cameras: cameras,
          zoom: currentZoom,
          session: session,
          editSession: editSession,
        );

        // Add suspected location bounds if one is selected
        if (appState.selectedSuspectedLocation != null) {
          final selectedLocation = appState.selectedSuspectedLocation!;
          if (selectedLocation.bounds.isNotEmpty) {
            overlays.add(
              Polygon(
                points: selectedLocation.bounds,
                color: Colors.orange.withOpacity(0.3),
                borderColor: Colors.orange,
                borderStrokeWidth: 2.0,
              ),
            );
          }
        }

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
                width: kNodeIconDiameter,
                height: kNodeIconDiameter,
                child: CameraIcon(
                  type: editSession != null ? CameraIconType.editing : CameraIconType.mock,
                ),
              ),
            );
          } catch (_) {
            // Controller not ready yet
          }
        }

        // Build provisional pin for navigation/search mode
        if (appState.showProvisionalPin && appState.provisionalPinLocation != null) {
          centerMarkers.add(
            Marker(
              point: appState.provisionalPinLocation!,
              width: 32.0,
              height: 32.0,
              child: const ProvisionalPin(),
            ),
          );
        }

        // Build start/end pins for route visualization
        if (appState.showingOverview || appState.isInRouteMode || appState.isSettingSecondPoint) {
          if (appState.routeStart != null) {
            centerMarkers.add(
              Marker(
                point: appState.routeStart!,
                width: 32.0,
                height: 32.0,
                child: const LocationPin(type: PinType.start),
              ),
            );
          }
          if (appState.routeEnd != null) {
            centerMarkers.add(
              Marker(
                point: appState.routeEnd!,
                width: 32.0,
                height: 32.0,
                child: const LocationPin(type: PinType.end),
              ),
            );
          }
        }

        // Build route path visualization
        final routeLines = <Polyline>[];
        if (appState.routePath != null && appState.routePath!.length > 1) {
          // Show route line during overview or active route
          if (appState.showingOverview || appState.isInRouteMode) {
            routeLines.add(Polyline(
              points: appState.routePath!,
              color: Colors.blue,
              strokeWidth: 4.0,
            ));
          }
        }

        return Stack(
          children: [
            PolygonLayer(polygons: overlays),
            if (editLines.isNotEmpty) PolylineLayer(polylines: editLines),
            if (routeLines.isNotEmpty) PolylineLayer(polylines: routeLines),
            MarkerLayer(markers: [...markers, ...suspectedLocationMarkers, ...centerMarkers]),
          ],
        );
      }
    );

    return Stack(
      children: [
        SheetAwareMap(
          sheetHeight: widget.sheetHeight,
          child: FlutterMap(
            key: ValueKey('map_${appState.offlineMode}_${appState.selectedTileType?.id ?? 'none'}_${_tileManager.mapRebuildKey}'),
            mapController: _controller.mapController,
            options: MapOptions(
              initialCenter: _gpsController.currentLocation ?? _positionManager.initialLocation ?? LatLng(37.7749, -122.4194),
            initialZoom: _positionManager.initialZoom ?? 15,
            maxZoom: (appState.selectedTileType?.maxZoom ?? 18).toDouble(),
            onPositionChanged: (pos, gesture) {
              setState(() {}); // Instant UI update for zoom, etc.
              if (gesture) widget.onUserGesture();
              
              if (session != null) {
                appState.updateSession(target: pos.center);
              }
              if (editSession != null) {
                appState.updateEditSession(target: pos.center);
              }
              
              // Update provisional pin location during navigation search/routing
              if (appState.showProvisionalPin) {
                appState.updateProvisionalPinLocation(pos.center);
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
              final minZoom = _getMinZoomForCameras(context);
              if (pos.zoom >= minZoom) {
                _cameraDebounce(_refreshCamerasFromProvider);
              } else {
                // Skip nodes at low zoom - report immediate completion (brutalist approach)
                NetworkStatus.instance.reportNodeComplete();
                
                // Show zoom warning if needed
                _showZoomWarningIfNeeded(context, pos.zoom, minZoom);
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
          onSearchPressed: widget.onSearchPressed,
        ),

        // Network status indicator (top-left) - conditionally shown
        if (appState.networkStatusIndicatorEnabled)
          const NetworkStatusIndicator(),
        
        // Proximity alert banner (top)
        ProximityAlertBanner(
          isVisible: _showProximityBanner,
          onDismiss: () {
            setState(() {
              _showProximityBanner = false;
            });
          },
        ),
      ],
    );
  }

  /// Build polylines connecting original cameras to their edited positions
  List<Polyline> _buildEditLines(List<OsmNode> cameras) {
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
            color: kNodeRingColorPending,
            strokeWidth: 3.0,
          ));
        }
      }
    }
    
    return lines;
  }
}


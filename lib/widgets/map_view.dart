import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart' show AppState, FollowMeMode, UploadMode;
import '../services/offline_area_service.dart';
import '../services/network_status.dart';

import '../models/osm_node.dart';
import '../models/node_profile.dart';
import '../models/suspected_location.dart';
import '../models/tile_provider.dart';
import '../state/session_state.dart';
import 'debouncer.dart';
import 'node_provider_with_cache.dart';
import 'map/map_overlays.dart';
import 'map/map_position_manager.dart';
import 'map/tile_layer_manager.dart';
import 'map/node_refresh_controller.dart';
import 'map/gps_controller.dart';
import 'map/map_data_manager.dart';
import 'map/map_interaction_manager.dart';
import 'map/marker_layer_builder.dart';
import 'map/overlay_layer_builder.dart';
import 'network_status_indicator.dart';
import 'node_limit_indicator.dart';
import 'proximity_alert_banner.dart';
import '../dev_config.dart';
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
    this.onNodeLimitChanged,
    this.onLocationStatusChanged,
  });

  final FollowMeMode followMeMode;
  final VoidCallback onUserGesture;
  final double sheetHeight;
  final int? selectedNodeId;
  final void Function(OsmNode)? onNodeTap;
  final void Function(SuspectedLocation)? onSuspectedLocationTap;
  final VoidCallback? onSearchPressed;
  final void Function(bool isLimited)? onNodeLimitChanged;
  final VoidCallback? onLocationStatusChanged;

  @override
  State<MapView> createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  late final AnimatedMapController _controller;
  final Debouncer _cameraDebounce = Debouncer(kDebounceCameraRefresh);
  final Debouncer _tileDebounce = Debouncer(const Duration(milliseconds: 150));
  final Debouncer _mapPositionDebounce = Debouncer(const Duration(milliseconds: 1000));
  final Debouncer _constrainedNodeSnapBack = Debouncer(const Duration(milliseconds: 100));

  late final MapPositionManager _positionManager;
  late final TileLayerManager _tileManager;
  late final NodeRefreshController _nodeController;
  late final GpsController _gpsController;
  late final MapDataManager _dataManager;
  late final MapInteractionManager _interactionManager;
  
  // Track zoom to clear queue on zoom changes
  double? _lastZoom;
  
  // Track map center to clear queue on significant panning
  LatLng? _lastCenter;
  
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
    _nodeController = NodeRefreshController();
    _nodeController.initialize(onNodesUpdated: _onNodesUpdated);
    _gpsController = GpsController();
    _dataManager = MapDataManager();
    _interactionManager = MapInteractionManager();
    
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
    _gpsController.initialize(
      mapController: _controller,
      onLocationUpdated: () {
        setState(() {});
        widget.onLocationStatusChanged?.call(); // Notify parent about location status change
      },
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
            LatLngBounds? mapBounds;
            try {
              mapBounds = _controller.mapController.camera.visibleBounds;
            } catch (_) {
              return [];
            }
            return mapBounds != null 
                ? NodeProviderWithCache.instance.getCachedNodesForBounds(mapBounds)
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
      onMapMovedProgrammatically: () {
        // Refresh nodes when GPS controller moves the map
        _refreshNodesFromProvider();
      },
    );

    // Fetch initial cameras
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNodesFromProvider();
    });
  }





  @override
  void dispose() {
    _cameraDebounce.dispose();
    _tileDebounce.dispose();
    _mapPositionDebounce.dispose();
    _nodeController.dispose();
    _tileManager.dispose();
    _gpsController.dispose();
    // PrefetchAreaService no longer used - replaced with NodeDataManager
    super.dispose();
  }



  void _onNodesUpdated() {
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
  
  /// Whether we currently have a valid GPS location
  bool get hasLocation => _gpsController.hasLocation;

  /// Expose static methods from MapPositionManager for external access
  static Future<void> clearStoredMapPosition() => 
      MapPositionManager.clearStoredMapPosition();




  void _refreshNodesFromProvider() {
    final appState = context.read<AppState>();
    _nodeController.refreshNodesFromProvider(
      controller: _controller,
      enabledProfiles: appState.enabledProfiles,
      uploadMode: appState.uploadMode,
      context: context,
    );
  }

  /// Calculate search bar offset for screen-positioned indicators
  double _calculateScreenIndicatorSearchOffset(AppState appState) {
    return (!appState.offlineMode && appState.isInSearchMode) ? 60.0 : 0.0;
  }


  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle follow-me mode changes - only if it actually changed
    if (widget.followMeMode != oldWidget.followMeMode) {
      _gpsController.updateFollowMeMode(
        newMode: widget.followMeMode,
        oldMode: oldWidget.followMeMode,
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final session = appState.session;
    final editSession = appState.editSession;

    // Check if enabled profiles changed and refresh nodes if needed
    _nodeController.checkAndHandleProfileChanges(
      currentEnabledProfiles: appState.enabledProfiles,
      onProfilesChanged: _refreshNodesFromProvider,
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
    
    // Check for pending snap backs (when extract checkbox is unchecked)
    final snapBackTarget = appState.consumePendingSnapBack();
    if (snapBackTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _controller.animateTo(
          dest: snapBackTarget,
          zoom: _controller.mapController.camera.zoom,
          curve: Curves.easeOut,
          duration: const Duration(milliseconds: 250),
        );
      });
    }
    
    // Edit sessions don't need to center - we're already centered from the node tap
    // SheetAwareMap handles the visual positioning
    
    // Get current zoom level and map bounds (shared by all logic)
    double currentZoom = 15.0; // fallback
    LatLngBounds? mapBounds;
    try {
      currentZoom = _controller.mapController.camera.zoom;
      mapBounds = _controller.mapController.camera.visibleBounds;
    } catch (_) {
      // Controller not ready yet, use fallback values
      mapBounds = null;
    }
    
    // Get node data using the data manager
    final nodeData = _dataManager.getNodesForRendering(
      currentZoom: currentZoom,
      mapBounds: mapBounds,
      uploadMode: appState.uploadMode,
      maxNodes: appState.maxNodes,
      onNodeLimitChanged: widget.onNodeLimitChanged,
    );
    
    // Build camera layers using the limited nodes
    Widget cameraLayers = LayoutBuilder(
      builder: (context, constraints) {
        
        // Build all marker layers
        final markerLayer = MarkerLayerBuilder.buildMarkerLayers(
          nodesToRender: nodeData.nodesToRender,
          mapController: _controller,
          appState: appState,
          session: session,
          editSession: editSession,
          selectedNodeId: widget.selectedNodeId,
          userLocation: _gpsController.currentLocation,
          currentZoom: currentZoom,
          mapBounds: mapBounds,
          onNodeTap: widget.onNodeTap,
          onSuspectedLocationTap: widget.onSuspectedLocationTap,
        );

        // Build all overlay layers
        final overlayLayers = OverlayLayerBuilder.buildOverlayLayers(
          nodesToRender: nodeData.nodesToRender,
          currentZoom: currentZoom,
          session: session,
          editSession: editSession,
          appState: appState,
          context: context,
        );

        return Stack(
          children: [
            ...overlayLayers,
            markerLayer,
          ],
        );
      },
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
            minZoom: 1.0,
            maxZoom: (appState.selectedTileType?.maxZoom ?? 18).toDouble(),
            interactionOptions: _interactionManager.getInteractionOptions(editSession),
            onPositionChanged: (pos, gesture) {
              setState(() {}); // Instant UI update for zoom, etc.
              if (gesture) {
                widget.onUserGesture();
              }
              
              // Enforce minimum zoom level for add/edit node sheets (but not tag sheet)
              if ((session != null || editSession != null) && pos.zoom < kMinZoomForNodeEditingSheets) {
                // User tried to zoom out below minimum - snap back to minimum zoom
                _controller.animateTo(
                  dest: pos.center,
                  zoom: kMinZoomForNodeEditingSheets.toDouble(),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
                return; // Don't process other position updates
              }
              
              if (session != null) {
                appState.updateSession(target: pos.center);
              }
              if (editSession != null) {
                // For constrained nodes that are not being extracted, always snap back to original position
                if (editSession.originalNode.isConstrained && !editSession.extractFromWay) {
                  final originalPos = editSession.originalNode.coord;
                  
                  // Always keep session target as original position
                  appState.updateEditSession(target: originalPos);
                  
                  // Only snap back if position actually drifted, and debounce to wait for gesture completion
                  if (pos.center.latitude != originalPos.latitude || pos.center.longitude != originalPos.longitude) {
                    _constrainedNodeSnapBack(() {
                      // Only animate if we're still in a constrained edit session and still drifted
                      final currentEditSession = appState.editSession;
                      if (currentEditSession?.originalNode.isConstrained == true && currentEditSession?.extractFromWay != true) {
                        final currentPos = _controller.mapController.camera.center;
                        if (currentPos.latitude != originalPos.latitude || currentPos.longitude != originalPos.longitude) {
                          _controller.animateTo(
                            dest: originalPos,
                            zoom: _controller.mapController.camera.zoom,
                            curve: Curves.easeOut,
                            duration: const Duration(milliseconds: 250),
                          );
                        }
                      }
                    });
                  }
                } else {
                  // Normal unconstrained node - allow position updates
                  appState.updateEditSession(target: pos.center);
                }
              }
              
              // Update provisional pin location during navigation search/routing
              if (appState.showProvisionalPin) {
                appState.updateProvisionalPinLocation(pos.center);
              }
              
              // Clear tile queue on tile level changes OR significant panning
              final currentZoom = pos.zoom;
              final currentCenter = pos.center;
              final currentTileLevel = currentZoom.round();
              final lastTileLevel = _lastZoom?.round();
              final tileLevelChanged = lastTileLevel != null && currentTileLevel != lastTileLevel;
              final centerMoved = _interactionManager.mapMovedSignificantly(currentCenter, _lastCenter);
              
              if (tileLevelChanged || centerMoved) {
                _tileDebounce(() {
                  // Use selective clearing to only cancel tiles that are no longer visible
                  try {
                    final currentBounds = _controller.mapController.camera.visibleBounds;
                    _tileManager.clearStaleRequests(currentBounds: currentBounds);
                  } catch (e) {
                    // Fallback to clearing all if bounds calculation fails
                    debugPrint('[MapView] Could not get current bounds for selective clearing: $e');
                    _tileManager.clearTileQueueImmediate();
                  }
                });
              }
              _lastZoom = currentZoom;
              _lastCenter = currentCenter;
              
              // Save map position (debounced to avoid excessive writes)
              _mapPositionDebounce(() {
                _positionManager.saveMapPosition(pos.center, pos.zoom);
              });
              
              // Request more nodes on any map movement/zoom at valid zoom level (slower debounce)
              final minZoom = _dataManager.getMinZoomForNodes(appState.uploadMode);
              if (pos.zoom >= minZoom) {
                _cameraDebounce(_refreshNodesFromProvider);
              } else {
                // Skip nodes at low zoom - no loading state needed
                // Show zoom warning if needed
                _dataManager.showZoomWarningIfNeeded(context, pos.zoom, appState.uploadMode);
              }
            },
          ),
          children: [
            _tileManager.buildTileLayer(
              selectedProvider: appState.selectedTileProvider,
              selectedTileType: appState.selectedTileType,
            ),
            cameraLayers,
            // Built-in scale bar from flutter_map, positioned relative to button bar with safe area
            Builder(
              builder: (context) {
                final safeArea = MediaQuery.of(context).padding;
                return Scalebar(
                  alignment: Alignment.bottomLeft,
                  padding: EdgeInsets.only(
                    left: leftPositionWithSafeArea(8, safeArea), 
                    bottom: bottomPositionFromButtonBar(kScaleBarSpacingAboveButtonBar, safeArea.bottom)
                  ),
                  textStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  lineColor: Colors.black,
                  strokeWidth: 3,
                  // backgroundColor removed in flutter_map >=8 (wrap in Container if needed)
                );
              },
            ),
          ],
        ),
        ),

        // All map overlays (mode indicator, zoom, attribution, add pin)
        MapOverlays(
          mapController: _controller,
          uploadMode: appState.uploadMode,
          session: session,
          editSession: editSession,
          attribution: appState.selectedTileType?.attribution,
          onSearchPressed: widget.onSearchPressed,
        ),

        // Node limit indicator (top-left) - shown when limit is active
        Builder(
          builder: (context) {
            final appState = context.watch<AppState>();
            final searchBarOffset = _calculateScreenIndicatorSearchOffset(appState);
            
            return NodeLimitIndicator(
              isActive: nodeData.isLimitActive,
              renderedCount: nodeData.nodesToRender.length,
              totalCount: nodeData.validNodesCount,
              top: 8.0 + searchBarOffset,
              left: 8.0,
            );
          },
        ),

        // Network status indicator (top-left) - conditionally shown
        if (appState.networkStatusIndicatorEnabled)
          Builder(
            builder: (context) {
              final appState = context.watch<AppState>();
              final searchBarOffset = _calculateScreenIndicatorSearchOffset(appState);
              final nodeLimitOffset = nodeData.isLimitActive ? 48.0 : 0.0; // Height of node limit indicator + spacing
              
              return NetworkStatusIndicator(
                top: 8.0 + searchBarOffset + nodeLimitOffset,
                left: 8.0,
              );
            },
          ),
        
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
}


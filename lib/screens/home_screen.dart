import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../widgets/map_view.dart';
import '../services/localization_service.dart';

import '../widgets/add_node_sheet.dart';
import '../widgets/edit_node_sheet.dart';
import '../widgets/node_tag_sheet.dart';
import '../widgets/camera_provider_with_cache.dart';
import '../widgets/download_area_dialog.dart';
import '../widgets/measured_sheet.dart';
import '../widgets/navigation_sheet.dart';
import '../widgets/search_bar.dart';
import '../models/osm_node.dart';
import '../models/search_result.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<MapViewState> _mapViewKey = GlobalKey<MapViewState>();
  late final AnimatedMapController _mapController;
  bool _editSheetShown = false;
  bool _navigationSheetShown = false;
  
  // Track sheet heights for map positioning
  double _addSheetHeight = 0.0;
  double _editSheetHeight = 0.0;
  double _tagSheetHeight = 0.0;
  double _navigationSheetHeight = 0.0;
  
  // Flag to prevent map bounce when transitioning from tag sheet to edit sheet
  bool _transitioningToEdit = false;
  
  // Track selected node for highlighting
  int? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  String _getFollowMeTooltip(FollowMeMode mode) {
    final locService = LocalizationService.instance;
    switch (mode) {
      case FollowMeMode.off:
        return locService.t('followMe.off');
      case FollowMeMode.northUp:
        return locService.t('followMe.northUp');
      case FollowMeMode.rotating:
        return locService.t('followMe.rotating');
    }
  }

  IconData _getFollowMeIcon(FollowMeMode mode) {
    switch (mode) {
      case FollowMeMode.off:
        return Icons.gps_off;
      case FollowMeMode.northUp:
        return Icons.gps_fixed;
      case FollowMeMode.rotating:
        return Icons.navigation;
    }
  }

  FollowMeMode _getNextFollowMeMode(FollowMeMode mode) {
    switch (mode) {
      case FollowMeMode.off:
        return FollowMeMode.northUp;
      case FollowMeMode.northUp:
        return FollowMeMode.rotating;
      case FollowMeMode.rotating:
        return FollowMeMode.off;
    }
  }

  void _openAddNodeSheet() {
    final appState = context.read<AppState>();
    // Disable follow-me when adding a camera so the map doesn't jump around
    appState.setFollowMeMode(FollowMeMode.off);
    
    appState.startAddSession();
    final session = appState.session!;          // guaranteed non‑null now

    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom, // Only safe area, no keyboard
        ),
        child: MeasuredSheet(
          onHeightChanged: (height) {
            setState(() {
              _addSheetHeight = height + MediaQuery.of(context).padding.bottom;
            });
          },
          child: AddNodeSheet(session: session),
        ),
      ),
    );
    
    // Reset height when sheet is dismissed
    controller.closed.then((_) {
      setState(() {
        _addSheetHeight = 0.0;
      });
    });
  }

  void _openEditNodeSheet() {
    final appState = context.read<AppState>();
    // Disable follow-me when editing a camera so the map doesn't jump around
    appState.setFollowMeMode(FollowMeMode.off);
    
    // Set transition flag to prevent map bounce
    _transitioningToEdit = true;
    
    // Close any existing tag sheet first
    if (_tagSheetHeight > 0) {
      Navigator.of(context).pop();
    }
    
    final session = appState.editSession!;     // should be non-null when this is called

    // Small delay to let tag sheet close smoothly
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      
      final controller = _scaffoldKey.currentState!.showBottomSheet(
        (ctx) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom, // Only safe area, no keyboard
          ),
          child: MeasuredSheet(
            onHeightChanged: (height) {
              setState(() {
                _editSheetHeight = height + MediaQuery.of(context).padding.bottom;
                // Clear transition flag and reset tag sheet height once edit sheet starts sizing
                if (height > 0 && _transitioningToEdit) {
                  _transitioningToEdit = false;
                  _tagSheetHeight = 0.0; // Now safe to reset
                  _selectedNodeId = null; // Clear selection when moving to edit
                }
              });
            },
            child: EditNodeSheet(session: session),
          ),
        ),
      );
      
      // Reset height when sheet is dismissed
      controller.closed.then((_) {
        setState(() {
          _editSheetHeight = 0.0;
          _transitioningToEdit = false;
        });
      });
    });
  }

  void _openNavigationSheet() {
    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom, // Only safe area, no keyboard
        ),
        child: MeasuredSheet(
          onHeightChanged: (height) {
            setState(() {
              _navigationSheetHeight = height + MediaQuery.of(context).padding.bottom;
            });
          },
          child: NavigationSheet(
            onStartRoute: _onStartRoute,
            onResumeRoute: _onResumeRoute,
          ),
        ),
      ),
    );
    
    // Reset height when sheet is dismissed
    controller.closed.then((_) {
      setState(() {
        _navigationSheetHeight = 0.0;
      });
      
      // Handle different dismissal scenarios
      final appState = context.read<AppState>();
      
      if (appState.isSettingSecondPoint) {
        // If user dismisses sheet while setting second point, cancel everything
        debugPrint('[HomeScreen] Sheet dismissed during second point selection - canceling navigation');
        appState.cancelNavigation();
      } else if (appState.isInRouteMode && appState.showingOverview) {
        // If we're in route active mode and showing overview, just hide the overview
        debugPrint('[HomeScreen] Sheet dismissed during route overview - hiding overview');
        appState.hideRouteOverview();
      }
    });
  }

  void _onStartRoute() {
    final appState = context.read<AppState>();
    
    // Get user location and check if we should auto-enable follow-me
    LatLng? userLocation;
    bool enableFollowMe = false;
    
    try {
      userLocation = _mapViewKey.currentState?.getUserLocation();
      if (userLocation != null && appState.shouldAutoEnableFollowMe(userLocation)) {
        debugPrint('[HomeScreen] Auto-enabling follow-me mode - user within 1km of start');
        appState.setFollowMeMode(FollowMeMode.northUp);
        enableFollowMe = true;
      }
    } catch (e) {
      debugPrint('[HomeScreen] Could not get user location for auto follow-me: $e');
    }
    
    // Start the route
    appState.startRoute();
    
    // Zoom to level 14 and center appropriately
    _zoomAndCenterForRoute(enableFollowMe, userLocation, appState.routeStart);
  }
  
  void _zoomAndCenterForRoute(bool followMeEnabled, LatLng? userLocation, LatLng? routeStart) {
    try {
      LatLng centerLocation;
      
      if (followMeEnabled && userLocation != null) {
        // Center on user if follow-me is enabled
        centerLocation = userLocation;
        debugPrint('[HomeScreen] Centering on user location for route start');
      } else if (routeStart != null) {
        // Center on start pin if user is far away or no GPS
        centerLocation = routeStart;
        debugPrint('[HomeScreen] Centering on route start pin');
      } else {
        debugPrint('[HomeScreen] No valid location to center on');
        return;
      }
      
      // Animate to zoom 14 and center location
      _mapController.animateTo(
        dest: centerLocation,
        zoom: 14.0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      debugPrint('[HomeScreen] Could not zoom/center for route: $e');
    }
  }
  
  void _onResumeRoute() {
    final appState = context.read<AppState>();
    
    // Hide the overview
    appState.hideRouteOverview();
    
    // Zoom and center for resumed route
    // For resume, we always center on user if GPS is available, otherwise start pin
    LatLng? userLocation;
    try {
      userLocation = _mapViewKey.currentState?.getUserLocation();
    } catch (e) {
      debugPrint('[HomeScreen] Could not get user location for route resume: $e');
    }
    
    _zoomAndCenterForRoute(
      appState.followMeMode != FollowMeMode.off, // Use current follow-me state
      userLocation, 
      appState.routeStart
    );
  }
  
  void _zoomToShowFullRoute(AppState appState) {
    if (appState.routeStart == null || appState.routeEnd == null) return;
    
    try {
      // Calculate the bounds of the route
      final start = appState.routeStart!;
      final end = appState.routeEnd!;
      
      // Find the center point between start and end
      final centerLat = (start.latitude + end.latitude) / 2;
      final centerLng = (start.longitude + end.longitude) / 2;
      final center = LatLng(centerLat, centerLng);
      
      // Calculate distance between points to determine appropriate zoom
      final distance = const Distance().as(LengthUnit.Meter, start, end);
      double zoom;
      if (distance < 500) {
        zoom = 16.0;
      } else if (distance < 2000) {
        zoom = 14.0;
      } else if (distance < 10000) {
        zoom = 12.0;
      } else {
        zoom = 10.0;
      }
      
      debugPrint('[HomeScreen] Zooming to show full route - distance: ${distance.toStringAsFixed(0)}m, zoom: $zoom');
      
      _mapController.animateTo(
        dest: center,
        zoom: zoom,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      debugPrint('[HomeScreen] Could not zoom to show full route: $e');
    }
  }

  void _onNavigationButtonPressed() {
    final appState = context.read<AppState>();
    
    debugPrint('[HomeScreen] Navigation button pressed - showRouteButton: ${appState.showRouteButton}, navigationMode: ${appState.navigationMode}');
    
    if (appState.showRouteButton) {
      // Route button - show route overview and zoom to show route
      debugPrint('[HomeScreen] Showing route overview');
      appState.showRouteOverview();
      
      // Zoom out a bit to show the full route when viewing overview
      _zoomToShowFullRoute(appState);
    } else {
      // Search button
      if (appState.offlineMode) {
        // Show offline snackbar instead of entering search mode
        debugPrint('[HomeScreen] Search disabled - offline mode');
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search not available while offline'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        // Enter search mode normally
        debugPrint('[HomeScreen] Entering search mode');
        try {
          final mapCenter = _mapController.mapController.camera.center;
          debugPrint('[HomeScreen] Map center: $mapCenter');
          appState.enterSearchMode(mapCenter);
        } catch (e) {
          // Controller not ready, use fallback location
          debugPrint('[HomeScreen] Map controller not ready: $e, using fallback');
          appState.enterSearchMode(LatLng(37.7749, -122.4194));
        }
      }
    }
  }

  void _onSearchResultSelected(SearchResult result) {
    final appState = context.read<AppState>();
    
    // Update navigation state with selected result
    appState.selectSearchResult(result);
    
    // Jump to the search result location
    try {
      _mapController.animateTo(
        dest: result.coordinates,
        zoom: 16.0, // Good zoom level for viewing the area
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // Map controller not ready, fallback to immediate move
      try {
        _mapController.mapController.move(result.coordinates, 16.0);
      } catch (_) {
        debugPrint('[HomeScreen] Could not move to search result: ${result.coordinates}');
      }
    }
  }

  void openNodeTagSheet(OsmNode node) {
    setState(() {
      _selectedNodeId = node.id; // Track selected node for highlighting
    });
    
    // Start smooth centering animation simultaneously with sheet opening
    // Use the same duration as SheetAwareMap (300ms) for coordinated animation
    try {
      _mapController.animateTo(
        dest: node.coord,
        zoom: _mapController.mapController.camera.zoom,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // Map controller not ready, fallback to immediate move
      try {
        _mapController.mapController.move(node.coord, _mapController.mapController.camera.zoom);
      } catch (_) {
        // Controller really not ready, skip centering
      }
    }
    
    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom, // Only safe area, no keyboard
        ),
        child: MeasuredSheet(
          onHeightChanged: (height) {
            setState(() {
              _tagSheetHeight = height + MediaQuery.of(context).padding.bottom;
            });
          },
          child: NodeTagSheet(
            node: node,
            onEditPressed: () {
              final appState = context.read<AppState>();
              appState.startEditSession(node);
              // This will trigger _openEditNodeSheet via the existing auto-show logic
            },
          ),
        ),
      ),
    );
    
    // Reset height and selection when sheet is dismissed (unless transitioning to edit)
    controller.closed.then((_) {
      if (!_transitioningToEdit) {
        setState(() {
          _tagSheetHeight = 0.0;
          _selectedNodeId = null; // Clear selection
        });
      }
      // If transitioning to edit, keep the height until edit sheet takes over
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Auto-open edit sheet when edit session starts
    if (appState.editSession != null && !_editSheetShown) {
      _editSheetShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditNodeSheet());
    } else if (appState.editSession == null) {
      _editSheetShown = false;
    }

    // Auto-open navigation sheet when needed - simplified logic (only in dev mode)
    if (kEnableNavigationFeatures) {
      final shouldShowNavSheet = appState.isInSearchMode || appState.showingOverview;
      if (shouldShowNavSheet && !_navigationSheetShown) {
        _navigationSheetShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openNavigationSheet());
      } else if (!shouldShowNavSheet) {
        _navigationSheetShown = false;
      }
    }

    // Pass the active sheet height directly to the map
    final activeSheetHeight = _addSheetHeight > 0 
        ? _addSheetHeight 
        : (_editSheetHeight > 0 
            ? _editSheetHeight 
            : (_navigationSheetHeight > 0
                ? _navigationSheetHeight
                : _tagSheetHeight));

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CameraProviderWithCache>(create: (_) => CameraProviderWithCache()),
      ],
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero),
        child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          automaticallyImplyLeading: false, // Disable automatic back button
          title: SvgPicture.asset(
            'assets/deflock-logo.svg',
            height: 28,
            fit: BoxFit.contain,
          ),
          actions: [
            IconButton(
              tooltip: _getFollowMeTooltip(appState.followMeMode),
              icon: Icon(_getFollowMeIcon(appState.followMeMode)),
              onPressed: () {
                final oldMode = appState.followMeMode;
                final newMode = _getNextFollowMeMode(oldMode);
                debugPrint('[HomeScreen] Follow mode changed: $oldMode → $newMode');
                appState.setFollowMeMode(newMode);
                // If enabling follow-me, retry location init in case permission was granted
                if (newMode != FollowMeMode.off) {
                  _mapViewKey.currentState?.retryLocationInit();
                }
              },
            ),
            AnimatedBuilder(
              animation: LocalizationService.instance,
              builder: (context, child) => IconButton(
                tooltip: LocalizationService.instance.settings,
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.pushNamed(context, '/settings'),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            MapView(
              key: _mapViewKey,
              controller: _mapController,
              followMeMode: appState.followMeMode,
              sheetHeight: activeSheetHeight,
              selectedNodeId: _selectedNodeId,
              onNodeTap: openNodeTagSheet,
              onSearchPressed: _onNavigationButtonPressed,
              onUserGesture: () {
                if (appState.followMeMode != FollowMeMode.off) {
                  appState.setFollowMeMode(FollowMeMode.off);
                }
              },
            ),
            // Search bar (slides in when in search mode) - only online since search doesn't work offline
            if (!appState.offlineMode && appState.isInSearchMode) 
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LocationSearchBar(
                  onResultSelected: _onSearchResultSelected,
                  onCancel: () => appState.cancelNavigation(),
                ),
              ),
            // Bottom button bar (restored to original)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom + kBottomButtonBarOffset,
                  left: 8,
                  right: 8,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600), // Match typical sheet width
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).shadowColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: Offset(0, -2),
                        )
                      ],
                    ),
                    margin: EdgeInsets.only(bottom: kBottomButtonBarOffset),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                    children: [
                      Expanded(
                        flex: 7, // 70% for primary action
                        child: AnimatedBuilder(
                          animation: LocalizationService.instance,
                          builder: (context, child) => ElevatedButton.icon(
                            icon: Icon(Icons.add_location_alt),
                            label: Text(LocalizationService.instance.tagNode),
                            onPressed: _openAddNodeSheet,
                            style: ElevatedButton.styleFrom(
                              minimumSize: Size(0, 48),
                              textStyle: TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        flex: 3, // 30% for secondary action
                        child: AnimatedBuilder(
                          animation: LocalizationService.instance,
                          builder: (context, child) => FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ElevatedButton.icon(
                              icon: Icon(Icons.download_for_offline),
                              label: Text(LocalizationService.instance.download),
                              onPressed: () => showDialog(
                                context: context,
                                builder: (ctx) => DownloadAreaDialog(controller: _mapController.mapController),
                              ),
                              style: ElevatedButton.styleFrom(
                                minimumSize: Size(0, 48),
                                textStyle: TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}


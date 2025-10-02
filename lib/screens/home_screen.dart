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
      (ctx) => MeasuredSheet(
        onHeightChanged: (height) {
          setState(() {
            _addSheetHeight = height;
          });
        },
        child: AddNodeSheet(session: session),
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
        (ctx) => MeasuredSheet(
          onHeightChanged: (height) {
            setState(() {
              _editSheetHeight = height;
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
      (ctx) => MeasuredSheet(
        onHeightChanged: (height) {
          setState(() {
            _navigationSheetHeight = height;
          });
        },
        child: NavigationSheet(
          onStartRoute: _onStartRoute,
        ),
      ),
    );
    
    // Reset height when sheet is dismissed
    controller.closed.then((_) {
      setState(() {
        _navigationSheetHeight = 0.0;
      });
      
      // If we're in route active mode and showing overview, reset the overview flag
      // This fixes the stuck route button issue
      final appState = context.read<AppState>();
      if (appState.isInRouteMode && appState.showingOverview) {
        debugPrint('[HomeScreen] Sheet dismissed during route overview - hiding overview');
        appState.hideRouteOverview();
      }
    });
  }

  void _onStartRoute() {
    final appState = context.read<AppState>();
    
    // Get user location from MapView GPS controller and check if we should auto-enable follow-me
    try {
      final userLocation = _mapViewKey.currentState?.getUserLocation();
      if (userLocation != null && appState.shouldAutoEnableFollowMe(userLocation)) {
        debugPrint('[HomeScreen] Auto-enabling follow-me mode - user within 1km of start');
        appState.setFollowMeMode(FollowMeMode.northUp);
      }
    } catch (e) {
      debugPrint('[HomeScreen] Could not get user location for auto follow-me: $e');
    }
    
    appState.startRoute();
  }

  void _onNavigationButtonPressed() {
    final appState = context.read<AppState>();
    
    debugPrint('[HomeScreen] Navigation button pressed - showRouteButton: ${appState.showRouteButton}, navigationMode: ${appState.navigationMode}');
    
    if (appState.showRouteButton) {
      // Route button - show route overview
      debugPrint('[HomeScreen] Showing route overview');
      appState.showRouteOverview();
    } else {
      // Search button - enter search mode
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
      (ctx) => MeasuredSheet(
        onHeightChanged: (height) {
          setState(() {
            _tagSheetHeight = height;
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

    // Auto-open navigation sheet when needed - simplified logic
    final shouldShowNavSheet = appState.isInSearchMode || appState.showingOverview;
    if (shouldShowNavSheet && !_navigationSheetShown) {
      _navigationSheetShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openNavigationSheet());
    } else if (!shouldShowNavSheet) {
      _navigationSheetShown = false;
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
            // Search bar (slides in when in search mode)
            if (appState.isInSearchMode) 
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
                        child: AnimatedBuilder(
                          animation: LocalizationService.instance,
                          builder: (context, child) => ElevatedButton.icon(
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
                    ],
                  ),
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


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
import '../widgets/download_area_dialog.dart';
import '../widgets/measured_sheet.dart';
import '../widgets/navigation_sheet.dart';
import '../widgets/search_bar.dart';
import '../widgets/suspected_location_sheet.dart';
import '../widgets/welcome_dialog.dart';
import '../widgets/changelog_dialog.dart';
import '../models/osm_node.dart';
import '../models/suspected_location.dart';
import '../models/search_result.dart';
import '../services/changelog_service.dart';
import 'coordinators/sheet_coordinator.dart';
import 'coordinators/navigation_coordinator.dart';
import 'coordinators/map_interaction_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<MapViewState> _mapViewKey = GlobalKey<MapViewState>();
  late final AnimatedMapController _mapController;
  
  // Coordinators for managing different aspects of the home screen
  late final SheetCoordinator _sheetCoordinator;
  late final NavigationCoordinator _navigationCoordinator;
  late final MapInteractionHandler _mapInteractionHandler;
  
  // Track node limit state for button disabling
  bool _isNodeLimitActive = false;
  
  // Track selected node for highlighting
  int? _selectedNodeId;
  
  // Track popup display to avoid showing multiple times
  bool _hasCheckedForPopup = false;

  @override
  void initState() {
    super.initState();
    _mapController = AnimatedMapController(vsync: this);
    _sheetCoordinator = SheetCoordinator();
    _navigationCoordinator = NavigationCoordinator();
    _mapInteractionHandler = MapInteractionHandler();
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
      case FollowMeMode.follow:
        return locService.t('followMe.follow');
      case FollowMeMode.rotating:
        return locService.t('followMe.rotating');
    }
  }

  IconData _getFollowMeIcon(FollowMeMode mode) {
    switch (mode) {
      case FollowMeMode.off:
        return Icons.gps_off;
      case FollowMeMode.follow:
        return Icons.gps_fixed;
      case FollowMeMode.rotating:
        return Icons.navigation;
    }
  }

  FollowMeMode _getNextFollowMeMode(FollowMeMode mode) {
    switch (mode) {
      case FollowMeMode.off:
        return FollowMeMode.follow;
      case FollowMeMode.follow:
        return FollowMeMode.rotating;
      case FollowMeMode.rotating:
        return FollowMeMode.off;
    }
  }

  void _openAddNodeSheet() {
    _sheetCoordinator.openAddNodeSheet(
      context: context,
      scaffoldKey: _scaffoldKey,
      mapController: _mapController,
      isNodeLimitActive: _isNodeLimitActive,
      onStateChanged: () => setState(() {}),
    );
  }

  void _openEditNodeSheet() {
    // Set transition flag BEFORE closing tag sheet to prevent map bounce
    _sheetCoordinator.setTransitioningToEdit(true);
    
    // Close any existing tag sheet first
    if (_sheetCoordinator.tagSheetHeight > 0) {
      Navigator.of(context).pop();
    }

    // Small delay to let tag sheet close smoothly
    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      
      _sheetCoordinator.openEditNodeSheet(
        context: context,
        scaffoldKey: _scaffoldKey,
        mapController: _mapController,
        onStateChanged: () {
          setState(() {
            // Clear tag sheet height and selected node when transitioning
            if (_sheetCoordinator.editSheetHeight > 0 && _sheetCoordinator.transitioningToEdit) {
              _sheetCoordinator.resetTagSheetHeight(() {});
              _selectedNodeId = null; // Clear selection when moving to edit
            }
          });
        },
      );
    });
  }

  void _openNavigationSheet() {
    _sheetCoordinator.openNavigationSheet(
      context: context,
      scaffoldKey: _scaffoldKey,
      onStateChanged: () => setState(() {}),
      onStartRoute: _onStartRoute,
      onResumeRoute: _onResumeRoute,
    );
  }

  // Check for and display welcome/changelog popup
  Future<void> _checkForPopup() async {
    if (!mounted) return;
    
    try {
      final appState = context.read<AppState>();
      
      // Run any needed migrations first
      final versionsNeedingMigration = await ChangelogService().getVersionsNeedingMigration();
      for (final version in versionsNeedingMigration) {
        await ChangelogService().runMigration(version, appState, context);
      }
      
      // Determine what popup to show
      final popupType = await ChangelogService().getPopupType();
      
      if (!mounted) return; // Check again after async operation
      
      switch (popupType) {
        case PopupType.welcome:
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const WelcomeDialog(),
          );
          break;
        
        case PopupType.changelog:
          final changelogContent = await ChangelogService().getChangelogContentForDisplay();
          if (changelogContent != null) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => ChangelogDialog(changelogContent: changelogContent),
            );
          }
          break;
        
        case PopupType.none:
          // No popup needed
          break;
      }
      
      // Complete the version change workflow (updates last seen version)
      await ChangelogService().completeVersionChange();
      
    } catch (e) {
      // Silently handle errors to avoid breaking the app launch
      debugPrint('[HomeScreen] Error checking for popup: $e');
      
      // Still complete version change to avoid getting stuck
      try {
        await ChangelogService().completeVersionChange();
      } catch (e2) {
        debugPrint('[HomeScreen] Error completing version change: $e2');
      }
    }
  }

  void _onStartRoute() {
    _navigationCoordinator.startRoute(
      context: context,
      mapController: _mapController,
      mapViewKey: _mapViewKey,
    );
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
    _navigationCoordinator.resumeRoute(
      context: context,
      mapController: _mapController,
      mapViewKey: _mapViewKey,
    );
  }
  


  void _onNavigationButtonPressed() {
    final appState = context.read<AppState>();
    
    if (appState.showRouteButton) {
      // Route button - show route overview and zoom to show route
      appState.showRouteOverview();
      _navigationCoordinator.zoomToShowFullRoute(
        appState: appState,
        mapController: _mapController,
      );
    } else {
      // Search/navigation button - delegate to coordinator
      _navigationCoordinator.handleNavigationButtonPress(
        context: context,
        mapController: _mapController,
      );
    }
  }

  void _onSearchResultSelected(SearchResult result) {
    _mapInteractionHandler.handleSearchResultSelection(
      context: context,
      result: result,
      mapController: _mapController,
    );
  }

  void openNodeTagSheet(OsmNode node) {
    // Handle the map interaction (centering and follow-me disable)
    _mapInteractionHandler.handleNodeTap(
      context: context,
      node: node,
      mapController: _mapController,
      onSelectedNodeChanged: (id) => setState(() => _selectedNodeId = id),
    );

    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom, // Only safe area, no keyboard
        ),
        child: MeasuredSheet(
          debugLabel: 'NodeTag',
          onHeightChanged: (height) {
            _sheetCoordinator.updateTagSheetHeight(
              height + MediaQuery.of(context).padding.bottom,
              () => setState(() {}),
            );
          },
          child: NodeTagSheet(
            node: node,
            isNodeLimitActive: _isNodeLimitActive,
            onEditPressed: () {
              // Check minimum zoom level before starting edit session
              final currentZoom = _mapController.mapController.camera.zoom;
              if (currentZoom < kMinZoomForNodeEditingSheets) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      LocalizationService.instance.t('editNode.zoomInRequiredMessage', 
                        params: [kMinZoomForNodeEditingSheets.toString()])
                    ),
                  ),
                );
                return;
              }
              
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
      if (!_sheetCoordinator.transitioningToEdit) {
        _sheetCoordinator.resetTagSheetHeight(() => setState(() {}));
        setState(() => _selectedNodeId = null);
      }
      // If transitioning to edit, keep the height until edit sheet takes over
    });
  }

  void openSuspectedLocationSheet(SuspectedLocation location) {
    // Handle the map interaction (centering and selection)
    _mapInteractionHandler.handleSuspectedLocationTap(
      context: context,
      location: location,
      mapController: _mapController,
    );

    final controller = _scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom, // Only safe area, no keyboard
        ),
        child: MeasuredSheet(
          debugLabel: 'SuspectedLocation',
          onHeightChanged: (height) {
            _sheetCoordinator.updateTagSheetHeight(
              height + MediaQuery.of(context).padding.bottom,
              () => setState(() {}),
            );
          },
          child: SuspectedLocationSheet(location: location),
        ),
      ),
    );
    
    // Reset height and clear selection when sheet is dismissed
    controller.closed.then((_) {
      _sheetCoordinator.resetTagSheetHeight(() => setState(() {}));
      context.read<AppState>().clearSuspectedLocationSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    // Auto-open edit sheet when edit session starts
    if (appState.editSession != null && !_sheetCoordinator.editSheetShown) {
      _sheetCoordinator.setEditSheetShown(true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEditNodeSheet());
    } else if (appState.editSession == null) {
      _sheetCoordinator.setEditSheetShown(false);
    }

    // Auto-open navigation sheet when needed - only when online and in nav features mode
    if (kEnableNavigationFeatures) {
      final shouldShowNavSheet = !appState.offlineMode && (appState.isInSearchMode || appState.showingOverview);
      if (shouldShowNavSheet && !_sheetCoordinator.navigationSheetShown) {
        _sheetCoordinator.setNavigationSheetShown(true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _openNavigationSheet());
      } else if (!shouldShowNavSheet && _sheetCoordinator.navigationSheetShown) {
        _sheetCoordinator.setNavigationSheetShown(false);
        // When sheet should close (including going offline), clean up navigation state
        if (appState.offlineMode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appState.cancelNavigation();
          });
        }
      }
    }

    // Check for welcome/changelog popup after app is fully initialized
    if (appState.isInitialized && !_hasCheckedForPopup) {
      _hasCheckedForPopup = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkForPopup();
        // Check if re-authentication is needed for message notifications
        appState.checkAndPromptReauthForMessages(context);
      });
    }

    // Pass the active sheet height directly to the map
    final activeSheetHeight = _sheetCoordinator.activeSheetHeight;

    return MediaQuery(
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
              builder: (context, child) {
                final appState = context.watch<AppState>();
                return IconButton(
                  tooltip: LocalizationService.instance.settings,
                  icon: Stack(
                    children: [
                      const Icon(Icons.settings),
                      if (appState.hasUnreadMessages)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                );
              },
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
              onSuspectedLocationTap: openSuspectedLocationSheet,
              onSearchPressed: _onNavigationButtonPressed,
              onNodeLimitChanged: (isLimited) {
                setState(() {
                  _isNodeLimitActive = isLimited;
                });
              },
              onUserGesture: () {
                _mapInteractionHandler.handleUserGesture(
                  context: context,
                  onSelectedNodeChanged: (id) => setState(() => _selectedNodeId = id),
                );
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
              child: Builder(
                builder: (context) {
                  final safeArea = MediaQuery.of(context).padding;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: safeArea.bottom + kBottomButtonBarOffset,
                      left: leftPositionWithSafeArea(8, safeArea),
                      right: rightPositionWithSafeArea(8, safeArea),
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
                                    onPressed: () {
                                      // Check minimum zoom level before opening download dialog
                                      final currentZoom = _mapController.mapController.camera.zoom;
                                      if (currentZoom < kMinZoomForOfflineDownload) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              LocalizationService.instance.t('download.areaTooBigMessage', 
                                                params: [kMinZoomForOfflineDownload.toString()])
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => DownloadAreaDialog(controller: _mapController.mapController),
                                      );
                                    },
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


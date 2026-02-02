import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../dev_config.dart';
import '../../services/localization_service.dart';
import '../../widgets/add_node_sheet.dart';
import '../../widgets/edit_node_sheet.dart';
import '../../widgets/navigation_sheet.dart';
import '../../widgets/measured_sheet.dart';

/// Coordinates all bottom sheet operations including opening, closing, height tracking,
/// and sheet-related validation logic.
class SheetCoordinator {
  // Track sheet heights for map positioning
  double _addSheetHeight = 0.0;
  double _editSheetHeight = 0.0;
  double _tagSheetHeight = 0.0;
  double _navigationSheetHeight = 0.0;
  
  // Track sheet state for auto-open logic
  bool _editSheetShown = false;
  bool _navigationSheetShown = false;
  
  // Flag to prevent map bounce when transitioning from tag sheet to edit sheet
  bool _transitioningToEdit = false;
  
  // Follow-me state restoration
  FollowMeMode? _followMeModeBeforeSheet;

  // Getters for accessing heights
  double get addSheetHeight => _addSheetHeight;
  double get editSheetHeight => _editSheetHeight;
  double get tagSheetHeight => _tagSheetHeight;
  double get navigationSheetHeight => _navigationSheetHeight;
  bool get editSheetShown => _editSheetShown;
  bool get navigationSheetShown => _navigationSheetShown;
  bool get transitioningToEdit => _transitioningToEdit;

  /// Get the currently active sheet height for map positioning
  double get activeSheetHeight {
    if (_addSheetHeight > 0) return _addSheetHeight;
    if (_editSheetHeight > 0) return _editSheetHeight;
    if (_navigationSheetHeight > 0) return _navigationSheetHeight;
    return _tagSheetHeight;
  }

  /// Update sheet state tracking
  void setEditSheetShown(bool shown) => _editSheetShown = shown;
  void setNavigationSheetShown(bool shown) => _navigationSheetShown = shown;
  void setTransitioningToEdit(bool transitioning) => _transitioningToEdit = transitioning;

  /// Open the add node sheet with validation and setup
  void openAddNodeSheet({
    required BuildContext context,
    required GlobalKey<ScaffoldState> scaffoldKey,
    required AnimatedMapController mapController,
    required bool isNodeLimitActive,
    required VoidCallback onStateChanged,
  }) {
    final appState = context.read<AppState>();
    
    // Check minimum zoom level before opening sheet
    final currentZoom = mapController.mapController.camera.zoom;
    if (currentZoom < kMinZoomForNodeEditingSheets) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalizationService.instance.t('editNode.zoomInRequiredMessage', 
              params: [kMinZoomForNodeEditingSheets.toString()])
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    // Check if node limit is active and warn user
    if (isNodeLimitActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalizationService.instance.t('nodeLimitIndicator.editingDisabledMessage')
          ),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    
    // Save current follow-me mode and disable it while sheet is open
    _followMeModeBeforeSheet = appState.followMeMode;
    appState.setFollowMeMode(FollowMeMode.off);
    
    appState.startAddSession();
    final session = appState.session!;          // guaranteed non‑null now

    final controller = scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom, // Only safe area, no keyboard
        ),
        child: MeasuredSheet(
          onHeightChanged: (height) {
            _addSheetHeight = height + MediaQuery.of(context).padding.bottom;
            onStateChanged();
          },
          child: AddNodeSheet(session: session),
        ),
      ),
    );
    
    // Reset height when sheet is dismissed
    controller.closed.then((_) {
      _addSheetHeight = 0.0;
      onStateChanged();
      
      // Handle dismissal by canceling session if still active
      final appState = context.read<AppState>();
      if (appState.session != null) {
        debugPrint('[SheetCoordinator] AddNodeSheet dismissed - canceling session');
        appState.cancelSession();
      }
      
      // Restore follow-me mode that was active before sheet opened
      _restoreFollowMeMode(appState);
    });
  }

  /// Open the edit node sheet with map centering
  void openEditNodeSheet({
    required BuildContext context,
    required GlobalKey<ScaffoldState> scaffoldKey,
    required AnimatedMapController mapController,
    required VoidCallback onStateChanged,
  }) {
    final appState = context.read<AppState>();
    
    // Save current follow-me mode and disable it while sheet is open  
    _followMeModeBeforeSheet = appState.followMeMode;
    appState.setFollowMeMode(FollowMeMode.off);
    
    final session = appState.editSession!;     // should be non-null when this is called
    
    // Center map on the node being edited
    try {
      mapController.animateTo(
        dest: session.originalNode.coord,
        zoom: mapController.mapController.camera.zoom,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // Map controller not ready, fallback to immediate move
      try {
        mapController.mapController.move(session.originalNode.coord, mapController.mapController.camera.zoom);
      } catch (_) {
        // Controller really not ready, skip centering
      }
    }
    
    // Set transition flag to prevent map bounce
    _transitioningToEdit = true;
    
    final controller = scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
        ),
        child: MeasuredSheet(
          onHeightChanged: (height) {
            final fullHeight = height + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
            _editSheetHeight = fullHeight;
            onStateChanged();
          },
          child: EditNodeSheet(session: session),
        ),
      ),
    );
    
    // Reset height and transition flag when sheet is dismissed
    controller.closed.then((_) {
      _editSheetHeight = 0.0;
      _transitioningToEdit = false;
      onStateChanged();
      
      // Handle dismissal by canceling session if still active
      final appState = context.read<AppState>();
      if (appState.editSession != null) {
        debugPrint('[SheetCoordinator] EditNodeSheet dismissed - canceling edit session');
        appState.cancelEditSession();
      }
      
      // Restore follow-me mode that was active before sheet opened
      _restoreFollowMeMode(appState);
    });
  }

  /// Open the navigation sheet for search/routing
  void openNavigationSheet({
    required BuildContext context,
    required GlobalKey<ScaffoldState> scaffoldKey,
    required VoidCallback onStateChanged,
    required VoidCallback onStartRoute,
    required VoidCallback onResumeRoute,
  }) {
    final controller = scaffoldKey.currentState!.showBottomSheet(
      (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
        ),
        child: MeasuredSheet(
          onHeightChanged: (height) {
            final fullHeight = height + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;
            _navigationSheetHeight = fullHeight;
            onStateChanged();
          },
          child: NavigationSheet(
            onStartRoute: onStartRoute,
            onResumeRoute: onResumeRoute,
          ),
        ),
      ),
    );
    
    // Reset height when sheet is dismissed
    controller.closed.then((_) {
      _navigationSheetHeight = 0.0;
      onStateChanged();
      
      // Handle different dismissal scenarios (from original HomeScreen logic)
      if (context.mounted) {
        final appState = context.read<AppState>();
        
        if (appState.isSettingSecondPoint) {
          // If user dismisses sheet while setting second point, cancel everything
          debugPrint('[SheetCoordinator] Sheet dismissed during second point selection - canceling navigation');
          appState.cancelNavigation();
        } else if (appState.isInRouteMode && appState.showingOverview) {
          // If we're in route active mode and showing overview, just hide the overview
          debugPrint('[SheetCoordinator] Sheet dismissed during route overview - hiding overview');
          appState.hideRouteOverview();
        }
      }
    });
  }

  /// Update tag sheet height (called externally)
  void updateTagSheetHeight(double height, VoidCallback onStateChanged) {
    debugPrint('[SheetCoordinator] Updating tag sheet height: $_tagSheetHeight -> $height');
    _tagSheetHeight = height;
    onStateChanged();
  }

  /// Reset tag sheet height
  void resetTagSheetHeight(VoidCallback onStateChanged) {
    debugPrint('[SheetCoordinator] Resetting tag sheet height from: $_tagSheetHeight');
    _tagSheetHeight = 0.0;
    onStateChanged();
  }

  /// Restore the follow-me mode that was active before opening a node sheet
  void _restoreFollowMeMode(AppState appState) {
    if (_followMeModeBeforeSheet != null) {
      debugPrint('[SheetCoordinator] Restoring follow-me mode: $_followMeModeBeforeSheet');
      appState.setFollowMeMode(_followMeModeBeforeSheet!);
      _followMeModeBeforeSheet = null; // Clear stored state
    }
  }

  /// Check if any node editing/viewing sheet is currently open
  bool get hasActiveNodeSheet => _addSheetHeight > 0 || _editSheetHeight > 0 || _tagSheetHeight > 0;
}
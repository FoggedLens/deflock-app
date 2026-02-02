import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../dev_config.dart';
import '../../services/localization_service.dart';
import '../compass_indicator.dart';
import 'layer_selector_button.dart';

/// Widget that renders all map overlay UI elements
class MapOverlays extends StatelessWidget {
  final AnimatedMapController mapController;
  final UploadMode uploadMode;
  final AddNodeSession? session;
  final EditNodeSession? editSession;
  final String? attribution; // Attribution for current tile provider
  final VoidCallback? onSearchPressed; // Callback for search button
  const MapOverlays({
    super.key,
    required this.mapController,
    required this.uploadMode,
    this.session,
    this.editSession,
    this.attribution,
    this.onSearchPressed,
  });

  /// Show full attribution text in a dialog
  void _showAttributionDialog(BuildContext context, String attribution) {
    final locService = LocalizationService.instance;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locService.t('mapTiles.attribution')),
        content: SelectableText(
          attribution,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(locService.t('actions.close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeArea = MediaQuery.of(context).padding;
    
    return Stack(
      children: [
        // MODE INDICATOR badge (top-right)
        if (uploadMode == UploadMode.sandbox || uploadMode == UploadMode.simulate)
          Positioned(
            top: topPositionWithSafeArea(18, safeArea),
            right: rightPositionWithSafeArea(14, safeArea),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: uploadMode == UploadMode.sandbox
                    ? Colors.orange.withOpacity(0.90)
                    : Colors.deepPurple.withOpacity(0.80),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(0,2)),
                ],
              ),
              child: Text(
                uploadMode == UploadMode.sandbox
                  ? 'SANDBOX MODE'
                  : 'SIMULATE',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),

        // Compass indicator (top-right, below mode indicator)
        CompassIndicator(
          mapController: mapController,
          safeArea: safeArea,
        ),

        // Zoom indicator, positioned relative to button bar with left safe area
        Positioned(
          left: leftPositionWithSafeArea(10, safeArea),
          bottom: bottomPositionFromButtonBar(kZoomIndicatorSpacingAboveButtonBar, safeArea.bottom),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.52),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Builder(
              builder: (context) {
                double zoom = 15.0; // fallback
                try {
                  zoom = mapController.mapController.camera.zoom;
                } catch (_) {
                  // Map controller not ready yet
                }
                return Text(
                  'Zoom: ${zoom.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
        ),

        // Attribution overlay, positioned relative to button bar with left safe area
        if (attribution != null)
          Positioned(
            bottom: bottomPositionFromButtonBar(kAttributionSpacingAboveButtonBar, safeArea.bottom),
            left: leftPositionWithSafeArea(10, safeArea),
            child: GestureDetector(
              onTap: () => _showAttributionDialog(context, attribution!),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                constraints: const BoxConstraints(maxWidth: 250),
                child: Text(
                  attribution!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ),

        // Zoom and layer controls (bottom-right), positioned relative to button bar with right safe area
        Positioned(
          bottom: bottomPositionFromButtonBar(kZoomControlsSpacingAboveButtonBar, safeArea.bottom),
          right: rightPositionWithSafeArea(16, safeArea),
          child: Consumer<AppState>(
            builder: (context, appState, child) {
              return Column(
                children: [
                  // Search/Navigation button - show search button always, show route button only in dev mode when online
                  if (onSearchPressed != null) ...[
                    if ((!appState.offlineMode && appState.showSearchButton) || appState.showRouteButton) ...[
                      FloatingActionButton(
                        mini: true,
                        heroTag: "search_nav",
                        onPressed: onSearchPressed,
                        tooltip: appState.showRouteButton 
                            ? LocalizationService.instance.t('navigation.routeOverview')
                            : LocalizationService.instance.t('navigation.searchLocation'),
                        child: Icon(appState.showRouteButton ? Icons.route : Icons.search),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  
                  // Layer selector button
                  const LayerSelectorButton(),
                  const SizedBox(height: 8),
                  // Zoom in button
                  FloatingActionButton(
                    mini: true,
                    heroTag: "zoom_in",
                    onPressed: () {
                      try {
                        final zoom = mapController.mapController.camera.zoom;
                        mapController.mapController.move(mapController.mapController.camera.center, zoom + 1);
                      } catch (_) {
                        // Map controller not ready yet
                      }
                    },
                    child: const Icon(Icons.add),
                  ),
                  const SizedBox(height: 8),
                  // Zoom out button  
                  FloatingActionButton(
                    mini: true,
                    heroTag: "zoom_out",
                    onPressed: () {
                      try {
                        final zoom = mapController.mapController.camera.zoom;
                        mapController.mapController.move(mapController.mapController.camera.center, zoom - 1);
                      } catch (_) {
                        // Map controller not ready yet
                      }
                    },
                    child: const Icon(Icons.remove),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
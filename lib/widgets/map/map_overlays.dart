import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../dev_config.dart';
import '../camera_icon.dart';
import 'layer_selector_button.dart';

/// Widget that renders all map overlay UI elements
class MapOverlays extends StatelessWidget {
  final MapController mapController;
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // MODE INDICATOR badge (top-right)
        if (uploadMode == UploadMode.sandbox || uploadMode == UploadMode.simulate)
          Positioned(
            top: 18,
            right: 14,
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

        // Zoom indicator, positioned relative to button bar
        Positioned(
          left: 10,
          bottom: bottomPositionFromButtonBar(kZoomIndicatorSpacingAboveButtonBar, MediaQuery.of(context).padding.bottom),
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
                  zoom = mapController.camera.zoom;
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

        // Attribution overlay, positioned relative to button bar
        if (attribution != null)
          Positioned(
            bottom: bottomPositionFromButtonBar(kAttributionSpacingAboveButtonBar, MediaQuery.of(context).padding.bottom),
            left: 10,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                attribution!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),

        // Zoom and layer controls (bottom-right), positioned relative to button bar
        Positioned(
          bottom: bottomPositionFromButtonBar(kZoomControlsSpacingAboveButtonBar, MediaQuery.of(context).padding.bottom),
          right: 16,
          child: Consumer<AppState>(
            builder: (context, appState, child) {
              return Column(
                children: [
                  // Search/Route button (top of controls) - hide when in search/route modes
                  if (onSearchPressed != null && !appState.isInSearchMode && !appState.isInRouteMode)
                    FloatingActionButton(
                      mini: true,
                      heroTag: "search_nav",
                      onPressed: onSearchPressed,
                      tooltip: appState.hasActiveRoute ? 'Route Overview' : 'Search Location',
                      child: Icon(appState.hasActiveRoute ? Icons.route : Icons.search),
                    ),
                  if (onSearchPressed != null && !appState.isInSearchMode && !appState.isInRouteMode) 
                    const SizedBox(height: 8),
                  
                  // Layer selector button
                  const LayerSelectorButton(),
                  const SizedBox(height: 8),
                  // Zoom in button
                  FloatingActionButton(
                    mini: true,
                    heroTag: "zoom_in",
                    onPressed: () {
                      try {
                        final zoom = mapController.camera.zoom;
                        mapController.move(mapController.camera.center, zoom + 1);
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
                        final zoom = mapController.camera.zoom;
                        mapController.move(mapController.camera.center, zoom - 1);
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
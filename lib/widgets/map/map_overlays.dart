import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../app_state.dart';
import '../../dev_config.dart';
import '../camera_icon.dart';
import 'layer_selector_button.dart';

/// Widget that renders all map overlay UI elements
class MapOverlays extends StatelessWidget {
  final MapController mapController;
  final UploadMode uploadMode;
  final AddCameraSession? session;
  final String? attribution; // Attribution for current tile provider

  const MapOverlays({
    super.key,
    required this.mapController,
    required this.uploadMode,
    this.session,
    this.attribution,
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

        // Zoom indicator, positioned above scale bar
        Positioned(
          left: 10,
          bottom: kZoomIndicatorBottomOffset,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.52),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Builder(
              builder: (context) {
                final zoom = mapController.camera.zoom;
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

        // Attribution overlay
        if (attribution != null)
          Positioned(
            bottom: kAttributionBottomOffset,
            left: 10,
            child: Container(
              color: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                attribution!,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),

        // Zoom and layer controls (bottom-right)
        Positioned(
          bottom: 80,
          right: 16,
          child: Column(
            children: [
              // Layer selector button
              const LayerSelectorButton(),
              const SizedBox(height: 8),
              // Zoom in button
              FloatingActionButton(
                mini: true,
                heroTag: "zoom_in",
                onPressed: () {
                  final zoom = mapController.camera.zoom;
                  mapController.move(mapController.camera.center, zoom + 1);
                },
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              // Zoom out button  
              FloatingActionButton(
                mini: true,
                heroTag: "zoom_out",
                onPressed: () {
                  final zoom = mapController.camera.zoom;
                  mapController.move(mapController.camera.center, zoom - 1);
                },
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),

        // Fixed pin when adding camera
        if (session != null)
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, kAddPinYOffset),
                child: const CameraIcon(type: CameraIconType.mock),
              ),
            ),
          ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../app_state.dart';
import '../../dev_config.dart';

/// Widget that renders all map overlay UI elements
class MapOverlays extends StatelessWidget {
  final MapController mapController;
  final UploadMode uploadMode;
  final AddCameraSession? session;

  const MapOverlays({
    super.key,
    required this.mapController,
    required this.uploadMode,
    this.session,
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
        Positioned(
          bottom: kAttributionBottomOffset,
          left: 10,
          child: Container(
            color: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: const Text(
              '© OpenStreetMap and contributors',
              style: TextStyle(fontSize: 11),
            ),
          ),
        ),

        // Fixed pin when adding camera
        if (session != null)
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, kAddPinYOffset),
                child: const Icon(Icons.place, size: 40, color: Colors.redAccent),
              ),
            ),
          ),
      ],
    );
  }
}
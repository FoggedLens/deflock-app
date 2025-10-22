import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// A compass indicator widget that shows the current map rotation and allows tapping to enable/disable north lock.
/// The compass appears in the top-right corner of the map and is disabled (non-interactive) when in follow+rotate mode.
class CompassIndicator extends StatefulWidget {
  final AnimatedMapController mapController;

  const CompassIndicator({
    super.key,
    required this.mapController,
  });

  @override
  State<CompassIndicator> createState() => _CompassIndicatorState();
}

class _CompassIndicatorState extends State<CompassIndicator> {
  double _lastRotation = 0.0;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        // Get current map rotation in degrees
        double rotationDegrees = 0.0;
        try {
          rotationDegrees = widget.mapController.mapController.camera.rotation;
        } catch (_) {
          // Map controller not ready yet
        }

        // Convert degrees to radians for Transform.rotate (flutter_map uses degrees)
        final rotationRadians = rotationDegrees * (pi / 180);

        // Check if we're in follow+rotate mode (compass should be disabled)
        final isDisabled = appState.followMeMode == FollowMeMode.rotating;
        final northLockEnabled = appState.northLockEnabled;

        // Force rebuild when north lock changes by comparing rotation
        if (northLockEnabled && rotationDegrees != _lastRotation) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
        _lastRotation = rotationDegrees;

        return Positioned(
          top: (appState.uploadMode == UploadMode.sandbox || appState.uploadMode == UploadMode.simulate) ? 60 : 18,
          right: 16,
          child: GestureDetector(
            onTap: isDisabled ? null : () {
              // Toggle north lock (but not when in follow+rotate mode)
              final newNorthLockEnabled = !northLockEnabled;
              appState.setNorthLockEnabled(newNorthLockEnabled);
              
              // If enabling north lock, animate to north-up orientation
              if (newNorthLockEnabled) {
                try {
                  widget.mapController.animateTo(
                    dest: widget.mapController.mapController.camera.center,
                    zoom: widget.mapController.mapController.camera.zoom,
                    rotation: 0.0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                  );
                } catch (_) {
                  // Controller not ready, ignore
                }
              }
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isDisabled 
                    ? Colors.grey.withOpacity(0.8)
                    : Colors.white.withOpacity(0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDisabled 
                      ? Colors.grey.shade400
                      : (northLockEnabled 
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300),
                  width: northLockEnabled ? 3.0 : 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  // Compass face with cardinal directions
                  Center(
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDisabled 
                            ? Colors.grey.shade200
                            : Colors.grey.shade50,
                      ),
                    ),
                  ),
                  // North indicator that rotates with map rotation
                  Transform.rotate(
                    angle: rotationRadians, // Rotate same direction as map rotation to counter-act it
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // North arrow (red triangle pointing up)
                          Container(
                            margin: const EdgeInsets.only(top: 6),
                            child: Icon(
                              Icons.keyboard_arrow_up,
                              size: 20,
                              color: isDisabled 
                                  ? Colors.grey.shade600
                                  : (northLockEnabled 
                                      ? Colors.red.shade700
                                      : Colors.red.shade600),
                            ),
                          ),
                          // Small 'N' label
                          Text(
                            'N',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDisabled 
                                  ? Colors.grey.shade600
                                  : (northLockEnabled 
                                      ? Colors.red.shade700
                                      : Colors.red.shade600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
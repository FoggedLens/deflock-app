import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// A compass indicator widget that shows the current map rotation and allows tapping to animate to north.
/// The compass appears in the top-right corner of the map and is disabled (non-interactive) when in follow+rotate mode.
class CompassIndicator extends StatefulWidget {
  final AnimatedMapController mapController;
  final EdgeInsets safeArea;

  const CompassIndicator({
    super.key,
    required this.mapController,
    required this.safeArea,
  });

  @override
  State<CompassIndicator> createState() => _CompassIndicatorState();
}

class _CompassIndicatorState extends State<CompassIndicator> {
  Timer? _animationTimer;

  @override
  void dispose() {
    _animationTimer?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
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

        final baseTop = (appState.uploadMode == UploadMode.sandbox || appState.uploadMode == UploadMode.simulate) ? 60 : 18;
        
        // Add extra spacing when search bar is visible
        final searchBarOffset = (!appState.offlineMode && appState.isInSearchMode) ? 60 : 0;
        
        return Positioned(
          top: baseTop + widget.safeArea.top + searchBarOffset,
          right: 16 + widget.safeArea.right,
          child: GestureDetector(
            onTap: isDisabled ? null : () {
              // Animate to north-up orientation
              try {
                // Cancel any existing animation timer
                _animationTimer?.cancel();
                
                // Start animation
                widget.mapController.animateTo(
                  dest: widget.mapController.mapController.camera.center,
                  zoom: widget.mapController.mapController.camera.zoom,
                  rotation: 0.0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                );
                
                // Start timer to force compass updates during animation
                // Update every 16ms (~60fps) for smooth visual rotation
                _animationTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
                  if (mounted) {
                    setState(() {});
                  }
                });
                
                // Stop the timer after animation completes (with small buffer)
                Timer(const Duration(milliseconds: 550), () {
                  _animationTimer?.cancel();
                  _animationTimer = null;
                  if (mounted) {
                    setState(() {}); // Final update to ensure correct end state
                  }
                });
              } catch (_) {
                // Controller not ready, ignore
              }
            },
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isDisabled 
                    ? Colors.grey.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.95),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDisabled 
                      ? Colors.grey.shade400
                      : Colors.grey.shade300,
                  width: 2.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
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
                                  : Colors.red.shade600,
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
                                  : Colors.red.shade600,
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
  }
}
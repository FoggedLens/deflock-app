import 'dart:ui';
import 'package:flutter/material.dart';

import '../dev_config.dart';
import '../services/localization_service.dart';

/// Overlay that appears over add/edit node sheets to guide users through 
/// the positioning tutorial. Shows a blurred background with tutorial text.
class PositioningTutorialOverlay extends StatelessWidget {
  const PositioningTutorialOverlay({
    super.key,
    this.onFadeOutComplete,
  });

  /// Called when the fade-out animation completes (if animated)
  final VoidCallback? onFadeOutComplete;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: kPositioningTutorialBlurSigma,
                sigmaY: kPositioningTutorialBlurSigma,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3), // Semi-transparent overlay
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tutorial icon
                        Icon(
                          Icons.pan_tool_outlined,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        
                        // Tutorial title
                        Text(
                          locService.t('positioningTutorial.title'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        
                        // Tutorial instructions
                        Text(
                          locService.t('positioningTutorial.instructions'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        
                        // Additional hint
                        Text(
                          locService.t('positioningTutorial.hint'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        );
      },
    );
  }
}
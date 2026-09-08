import 'dart:ui';
import 'package:flutter/material.dart';

import '../dev_config.dart';
import '../services/localization_service.dart';

/// Overlay that appears over add/edit node sheets to guide users through
/// the positioning tutorial. Shows a blurred background with tutorial text.
///
/// Stability note: on Android's Impeller (Vulkan) renderer, BackdropFilter
/// snapshots the render pass's "back texture" mid-frame. If that snapshot
/// races against the surface being invalidated - which happens constantly
/// right where this overlay lives, since the enclosing bottom sheet resizes
/// on open/keyboard/rotation - Impeller can hit a null texture and hard-abort
/// the whole process natively (not a catchable Dart error). Two things keep
/// that race from being triggered here:
///  - [RepaintBoundary] isolates the filter onto its own stable composited
///    layer instead of sharing one with the actively-resizing sheet.
///  - The widget is always kept mounted by the parent sheet and toggles
///    visibility via a fade (see [visible]) rather than being abruptly
///    inserted/removed from the tree, which is believed to be the other half
///    of what triggers the crash.
class PositioningTutorialOverlay extends StatefulWidget {
  const PositioningTutorialOverlay({
    super.key,
    required this.visible,
    this.onFadeOutComplete,
  });

  /// Whether the tutorial should currently be showing. Toggling this fades
  /// the overlay in/out - see class doc for why it's never removed from
  /// the tree instead.
  final bool visible;

  /// Called when the fade-out animation completes (i.e. the overlay has
  /// become fully transparent after [visible] turned false).
  final VoidCallback? onFadeOutComplete;

  @override
  State<PositioningTutorialOverlay> createState() => _PositioningTutorialOverlayState();
}

class _PositioningTutorialOverlayState extends State<PositioningTutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: widget.visible ? 1.0 : 0.0,
    );
    _controller.addStatusListener(_onStatusChanged);
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      widget.onFadeOutComplete?.call();
    }
  }

  @override
  void didUpdateWidget(covariant PositioningTutorialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatusChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ignore touches when faded out so the invisible-but-still-mounted
    // overlay doesn't block interaction with the sheet underneath.
    return IgnorePointer(
      ignoring: !widget.visible,
      child: FadeTransition(
        opacity: _controller,
        child: AnimatedBuilder(
          animation: LocalizationService.instance,
          builder: (context, child) {
            final locService = LocalizationService.instance;

            return ClipRect(
              child: RepaintBoundary(
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
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../dev_config.dart';

enum CameraIconType {
  real, // Blue ring - real cameras from OSM
  aging, // Fading ring - staleness in progress (real -> stale gradient)
  stale, // Brown ring - stale cameras from OSM
  mock, // White ring - add camera mock point
  pending, // Purple ring - submitted/pending cameras
  editing, // Orange ring - camera being edited
  pendingEdit, // Grey ring - original camera with pending edit
  pendingDeletion, // Red ring - camera pending deletion
}

/// Simple camera icon with grey dot and colored ring
class CameraIcon extends StatelessWidget {
  final CameraIconType type;
  final double agingProgress;

  const CameraIcon({super.key, required this.type, this.agingProgress = 0.0});

  Color get _ringColor {
    switch (type) {
      case CameraIconType.real:
        return kNodeRingColorReal;
      case CameraIconType.stale:
        return kNodeRingColorStale;
      case CameraIconType.aging:
        return _computeAgingColor(agingProgress);
      case CameraIconType.mock:
        return kNodeRingColorMock;
      case CameraIconType.pending:
        return kNodeRingColorPending;
      case CameraIconType.editing:
        return kNodeRingColorEditing;
      case CameraIconType.pendingEdit:
        return kNodeRingColorPendingEdit;
      case CameraIconType.pendingDeletion:
        return kNodeRingColorPendingDeletion;
    }
  }

  /// Interpolates between the real (fresh) ring color and the stale ring
  /// color based on aging progress (0.0 = just aged past the fresh window,
  /// 1.0 = fully stale).
  Color _computeAgingColor(double progress) {
    return Color.lerp(
      kNodeRingColorReal,
      kNodeRingColorStale,
      progress.clamp(0.0, 1.0),
    )!;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kNodeIconDiameter,
      height: kNodeIconDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _ringColor.withValues(alpha: kNodeDotOpacity),
        border: Border.all(
          color: _ringColor,
          width: getNodeRingThickness(context),
        ),
      ),
    );
  }
}

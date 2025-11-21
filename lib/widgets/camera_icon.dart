import 'package:flutter/material.dart';
import '../dev_config.dart';

enum CameraIconType {
  real,           // Blue ring - real cameras from OSM
  mock,           // White ring - add camera mock point
  pending,        // Purple ring - submitted/pending cameras
  editing,        // Orange ring - camera being edited
  pendingEdit,    // Grey ring - original camera with pending edit
  pendingDeletion, // Red ring - camera pending deletion
}

/// Simple camera icon with grey dot and colored ring
class CameraIcon extends StatelessWidget {
  final CameraIconType type;
  
  const CameraIcon({super.key, required this.type});

  Color get _ringColor {
    switch (type) {
      case CameraIconType.real:
        return dev.kNodeRingColorReal;
      case CameraIconType.mock:
        return dev.kNodeRingColorMock;
      case CameraIconType.pending:
        return dev.kNodeRingColorPending;
      case CameraIconType.editing:
        return dev.kNodeRingColorEditing;
      case CameraIconType.pendingEdit:
        return dev.kNodeRingColorPendingEdit;
      case CameraIconType.pendingDeletion:
        return dev.kNodeRingColorPendingDeletion;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: dev.kNodeIconDiameter,
      height: dev.kNodeIconDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _ringColor.withOpacity(dev.kNodeDotOpacity),
        border: Border.all(
          color: _ringColor,
          width: getNodeRingThickness(context),
        ),
      ),
    );
  }
}
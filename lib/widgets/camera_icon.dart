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
        return kNodeRingColorReal;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kNodeIconDiameter,
      height: kNodeIconDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(kNodeDotOpacity),
        border: Border.all(
          color: _ringColor,
          width: kNodeRingThickness,
        ),
      ),
    );
  }
}
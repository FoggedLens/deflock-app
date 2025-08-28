import 'package:flutter/material.dart';
import '../dev_config.dart';

enum CameraIconType {
  real,     // Blue ring - real cameras from OSM
  mock,     // White ring - add camera mock point
  pending,  // Purple ring - submitted/pending cameras
  editing,  // Orange ring - camera being edited
}

/// Simple camera icon with grey dot and colored ring
class CameraIcon extends StatelessWidget {
  final CameraIconType type;
  
  const CameraIcon({super.key, required this.type});

  Color get _ringColor {
    switch (type) {
      case CameraIconType.real:
        return kCameraRingColorReal;
      case CameraIconType.mock:
        return kCameraRingColorMock;
      case CameraIconType.pending:
        return kCameraRingColorPending;
      case CameraIconType.editing:
        return kCameraRingColorEditing;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kCameraIconDiameter,
      height: kCameraIconDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(kCameraDotOpacity),
        border: Border.all(
          color: _ringColor,
          width: kCameraRingThickness,
        ),
      ),
    );
  }
}
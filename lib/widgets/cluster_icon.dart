import 'package:flutter/material.dart';
import '../dev_config.dart';

/// Cluster icon showing a blue circle with white count text
class ClusterIcon extends StatelessWidget {
  final int count;

  const ClusterIcon({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kClusterIconDiameter,
      height: kClusterIconDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kNodeRingColorReal.withValues(alpha: 0.7),
        border: Border.all(color: kNodeRingColorReal, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

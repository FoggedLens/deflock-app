import '../models/node_profile.dart';

/// Formats editor direction values exactly as they will be queued for upload.
class DirectionSubmissionFormatter {
  const DirectionSubmissionFormatter._();

  static Object format(List<double> directions, NodeProfile? profile) {
    if (directions.isEmpty) return 0.0;

    final fov = profile?.fov;
    if (fov != null && fov > 0) {
      final ranges = directions
          .map((center) => _formatDirectionWithFov(center, fov))
          .toList();
      return ranges.length == 1 ? ranges.first : ranges.join(';');
    }

    if (directions.length == 1) return directions.first;
    return directions
        .map((direction) => direction.round().toString())
        .join(';');
  }

  static String _formatDirectionWithFov(double center, double fov) {
    if (fov >= 360) return '0-360';

    final halfFov = fov / 2;
    final start = (center - halfFov + 360) % 360;
    final end = (center + halfFov) % 360;
    return '${start.round()}-${end.round()}';
  }
}

/// Represents a direction with its associated field-of-view (FOV) cone.
class DirectionFov {
  /// The center direction in degrees (0-359, where 0 is north)
  final double centerDegrees;
  
  /// The field-of-view width in degrees (e.g., 35, 90, 180, 360)
  final double fovDegrees;
  
  DirectionFov(this.centerDegrees, this.fovDegrees);
  
  @override
  String toString() => 'DirectionFov(center: ${centerDegrees}°, fov: ${fovDegrees}°)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DirectionFov &&
          runtimeType == other.runtimeType &&
          centerDegrees == other.centerDegrees &&
          fovDegrees == other.fovDegrees;
          
  @override
  int get hashCode => centerDegrees.hashCode ^ fovDegrees.hashCode;
}
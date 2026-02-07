import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../state/settings_state.dart';

/// Custom scale bar widget that respects user's distance unit preference
/// 
/// Replaces flutter_map's built-in Scalebar to support metric/imperial units.
/// Uses the existing DistanceUnit enum from SettingsState.
/// 
/// Based on the brutalist code philosophy: simple, explicit, maintainable.
class CustomScaleBar extends StatelessWidget {
  const CustomScaleBar({
    super.key,
    this.maxWidthPx = 120,
    this.barHeight = 8,
    this.padding = const EdgeInsets.all(10),
    this.alignment = Alignment.bottomLeft,
    this.textStyle,
  });

  final double maxWidthPx;
  final double barHeight;
  final EdgeInsets padding;
  final Alignment alignment;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final camera = MapCamera.of(context);
        final center = camera.center;
        final zoom = camera.zoom;

        // Calculate meters represented by maxWidthPx at current zoom around map center
        final maxMeters = _metersForPixelSpan(camera, center, zoom, maxWidthPx);
        
        // Calculate nice intervals in the display unit for better user experience
        final niceMeters = _niceDistanceInDisplayUnit(maxMeters, appState.distanceUnit);

        // Calculate actual bar width in pixels
        final metersPerPx = maxMeters / maxWidthPx;
        final barWidthPx = (niceMeters / metersPerPx).clamp(1.0, maxWidthPx);

        // Format the label based on user's unit preference
        final label = _formatLabel(niceMeters, appState.distanceUnit);

        // Use styling that matches the original flutter_map scale bar
        final style = textStyle ??
            const TextStyle(
              fontSize: 12,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            );

        return Align(
          alignment: alignment,
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                const SizedBox(height: 2),
                CustomPaint(
                  size: Size(barWidthPx, barHeight + 6),
                  painter: _ScaleBarPainter(barHeight: barHeight),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Calculate the real-world distance represented by a pixel span at the current zoom level
  /// 
  /// Uses a simple approach: calculate the distance between two points that are
  /// separated by the pixel span at the map center latitude.
  double _metersForPixelSpan(
    MapCamera camera,
    LatLng center,
    double zoom,
    double pixelSpan,
  ) {
    // At the equator, 1 degree of longitude = ~111,320 meters
    // At other latitudes, it's scaled by cos(latitude)
    const metersPerDegreeAtEquator = 111320.0;
    final metersPerDegreeLongitude = metersPerDegreeAtEquator * math.cos(center.latitude * math.pi / 180);
    
    // Calculate degrees per pixel at this zoom level
    // Web Mercator: 360 degrees spans 2^zoom tiles, each tile is 256 pixels
    final tilesAtZoom = math.pow(2, zoom);
    final pixelsAtZoom = tilesAtZoom * 256;
    final degreesPerPixel = 360.0 / pixelsAtZoom;
    
    // Calculate the longitude span represented by our pixel span
    final longitudeSpan = degreesPerPixel * pixelSpan;
    
    // Convert to meters
    return longitudeSpan * metersPerDegreeLongitude;
  }

  /// Convert a maximum distance to a "nice" rounded distance in the display unit
  /// 
  /// For metric: Nice intervals like 1m, 2m, 5m, 10m, 1km, 2km, 5km
  /// For imperial: Nice intervals like 1ft, 2ft, 5ft, 10ft, 1mi, 2mi, 5mi
  double _niceDistanceInDisplayUnit(double maxMeters, DistanceUnit unit) {
    if (maxMeters <= 0) return 0;

    switch (unit) {
      case DistanceUnit.metric:
        return _calculateNiceDistance(maxMeters, [
          // Small metric intervals (meters)
          1, 2, 5, 10, 20, 50, 100, 200, 500,
          // Large metric intervals (kilometers, converted to meters)
          1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000,
          1000000, 2000000, 5000000, 10000000,
        ]);

      case DistanceUnit.imperial:
        const feetToMeters = 0.3048;
        const milesToMeters = 1609.34;
        
        return _calculateNiceDistance(maxMeters, [
          // Small imperial intervals (feet, converted to meters)
          1 * feetToMeters,
          2 * feetToMeters, 
          5 * feetToMeters,
          10 * feetToMeters,
          20 * feetToMeters,
          50 * feetToMeters,
          100 * feetToMeters,
          200 * feetToMeters,
          500 * feetToMeters,
          1000 * feetToMeters,
          2000 * feetToMeters,
          5000 * feetToMeters,
          // Large imperial intervals (miles, converted to meters)
          1 * milesToMeters,
          2 * milesToMeters,
          5 * milesToMeters,
          10 * milesToMeters,
          20 * milesToMeters,
          50 * milesToMeters,
          100 * milesToMeters,
          200 * milesToMeters,
          500 * milesToMeters,
          1000 * milesToMeters,
        ]);
    }
  }

  /// Find the largest "nice" distance that fits within the maximum
  double _calculateNiceDistance(double maxMeters, List<double> intervals) {
    // Find the largest interval that's still smaller than our max
    for (int i = intervals.length - 1; i >= 0; i--) {
      if (intervals[i] <= maxMeters) {
        return intervals[i];
      }
    }
    // Fallback to smallest interval if none fit
    return intervals.first;
  }

  /// Format the distance label according to the user's unit preference
  /// 
  /// Uses the same logic as DistanceService for consistency:
  /// - Metric: meters < 1000m, kilometers ≥ 1000m  
  /// - Imperial: feet < 5280ft, miles ≥ 5280ft
  String _formatLabel(double meters, DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.metric:
        if (meters >= 1000) {
          final km = meters / 1000.0;
          return '${_trim(km)} km';
        }
        return '${meters.round()} m';

      case DistanceUnit.imperial:
        final feet = meters * 3.28084;
        if (feet >= 5280) {
          final miles = feet / 5280.0;
          return '${_trim(miles)} mi';
        }
        return '${feet.round()} ft';
    }
  }

  /// Trim unnecessary decimal places from distance values
  String _trim(double v) {
    if (v >= 100) return v.toStringAsFixed(0);
    if (v >= 10) return v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return v
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

/// Custom painter for drawing the scale bar
/// 
/// Draws a simple horizontal line with vertical end markers,
/// matching the style of the original flutter_map scale bar.
class _ScaleBarPainter extends CustomPainter {
  _ScaleBarPainter({required this.barHeight});
  
  final double barHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3  // Match original scale bar stroke width
      ..style = PaintingStyle.stroke;

    final yTop = 2.0;
    final yBottom = yTop + barHeight;

    // Draw horizontal base line
    canvas.drawLine(Offset(0, yBottom), Offset(size.width, yBottom), paint);
    
    // Draw left vertical marker
    canvas.drawLine(Offset(0, yTop), Offset(0, yBottom), paint);
    
    // Draw right vertical marker
    canvas.drawLine(Offset(size.width, yTop), Offset(size.width, yBottom), paint);

    // Draw middle marker for longer scales (visual clarity)
    if (size.width >= 40) {
      final midX = size.width / 2;
      canvas.drawLine(
        Offset(midX, yBottom - barHeight * 0.6),
        Offset(midX, yBottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScaleBarPainter oldDelegate) =>
      oldDelegate.barHeight != barHeight;
}
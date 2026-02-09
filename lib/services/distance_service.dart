import '../state/settings_state.dart';

/// Service for distance unit conversions and formatting
/// 
/// Follows brutalist principles: simple, explicit conversions without fancy abstractions.
/// All APIs work in metric units (meters/km), this service only handles display formatting.
class DistanceService {
  // Conversion constants
  static const double _metersToFeet = 3.28084;
  static const double _metersToMiles = 0.000621371;

  /// Format distance for display based on unit preference
  /// 
  /// For metric: uses meters for < 1000m, kilometers for >= 1000m
  /// For imperial: uses feet for < 5280ft (1 mile), miles for >= 5280ft
  static String formatDistance(double distanceInMeters, DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.metric:
        if (distanceInMeters < 1000) {
          return '${distanceInMeters.round()} m';
        } else {
          return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
        }
      
      case DistanceUnit.imperial:
        final distanceInFeet = distanceInMeters * _metersToFeet;
        if (distanceInFeet < 5280) {
          return '${distanceInFeet.round()} ft';
        } else {
          final distanceInMiles = distanceInMeters * _metersToMiles;
          return '${distanceInMiles.toStringAsFixed(1)} mi';
        }
    }
  }

  /// Format large distances (like route distances) for display
  /// 
  /// Always uses the larger unit (km/miles) for routes
  static String formatRouteDistance(double distanceInMeters, DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.metric:
        return '${(distanceInMeters / 1000).toStringAsFixed(1)} km';
      
      case DistanceUnit.imperial:
        final distanceInMiles = distanceInMeters * _metersToMiles;
        return '${distanceInMiles.toStringAsFixed(1)} mi';
    }
  }

  /// Get the unit suffix for small distances (used in form fields, etc.)
  static String getSmallDistanceUnit(DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.metric:
        return 'm';
      case DistanceUnit.imperial:
        return 'ft';
    }
  }

  /// Convert displayed distance value back to meters for API usage
  /// 
  /// This is for form fields where users enter values in their preferred units
  static double convertToMeters(double value, DistanceUnit unit, {bool isSmallDistance = true}) {
    switch (unit) {
      case DistanceUnit.metric:
        return isSmallDistance ? value : value * 1000; // m or km to m
      
      case DistanceUnit.imperial:
        if (isSmallDistance) {
          return value / _metersToFeet; // ft to m
        } else {
          return value / _metersToMiles; // miles to m
        }
    }
  }

  /// Convert meters to the preferred small distance unit for form display
  static double convertFromMeters(double meters, DistanceUnit unit) {
    switch (unit) {
      case DistanceUnit.metric:
        return meters;
      
      case DistanceUnit.imperial:
        return meters * _metersToFeet;
    }
  }
}
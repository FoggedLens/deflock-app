import 'package:latlong2/latlong.dart';

/// Represents a search result from a geocoding service
class SearchResult {
  final String displayName;
  final LatLng coordinates;
  final String? category;
  final String? type;
  
  const SearchResult({
    required this.displayName,
    required this.coordinates,
    this.category,
    this.type,
  });
  
  /// Create SearchResult from Nominatim JSON response
  factory SearchResult.fromNominatim(Map<String, dynamic> json) {
    final lat = double.parse(json['lat'] as String);
    final lon = double.parse(json['lon'] as String);
    
    return SearchResult(
      displayName: json['display_name'] as String,
      coordinates: LatLng(lat, lon),
      category: json['category'] as String?,
      type: json['type'] as String?,
    );
  }
  
  @override
  String toString() {
    return 'SearchResult(displayName: $displayName, coordinates: $coordinates)';
  }
  
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchResult &&
        other.displayName == displayName &&
        other.coordinates == coordinates;
  }
  
  @override
  int get hashCode {
    return displayName.hashCode ^ coordinates.hashCode;
  }
}
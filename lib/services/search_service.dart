import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

import '../models/search_result.dart';
import 'http_client.dart';

class SearchService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const int _maxResults = 5;
  static const Duration _timeout = Duration(seconds: 10);
  final _client = UserAgentClient();
  
  /// Search for places using Nominatim geocoding service
  Future<List<SearchResult>> search(String query, {LatLngBounds? viewbox}) async {
    if (query.trim().isEmpty) {
      return [];
    }

    // Check if query looks like coordinates first
    final coordResult = _tryParseCoordinates(query.trim());
    if (coordResult != null) {
      return [coordResult];
    }

    // Otherwise, use Nominatim API
    return await _searchNominatim(query.trim(), viewbox: viewbox);
  }
  
  /// Try to parse various coordinate formats
  SearchResult? _tryParseCoordinates(String query) {
    // Remove common separators and normalize
    final normalized = query.replaceAll(RegExp(r'[,;]'), ' ').trim();
    final parts = normalized.split(RegExp(r'\s+'));
    
    if (parts.length != 2) return null;
    
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    
    if (lat == null || lon == null) return null;
    
    // Basic validation for Earth coordinates
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
    
    return SearchResult(
      displayName: 'Coordinates: ${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)}',
      coordinates: LatLng(lat, lon),
      category: 'coordinates',
      type: 'point',
    );
  }
  
  /// Search using Nominatim API
  Future<List<SearchResult>> _searchNominatim(String query, {LatLngBounds? viewbox}) async {
    final params = {
      'q': query,
      'format': 'json',
      'limit': _maxResults.toString(),
      'addressdetails': '1',
      'extratags': '1',
    };

    if (viewbox != null) {
      double round1(double v) => (v * 10).round() / 10;
      var west = round1(viewbox.west);
      var east = round1(viewbox.east);
      var south = round1(viewbox.south);
      var north = round1(viewbox.north);

      if (east - west < 0.5) {
        final mid = (east + west) / 2;
        west = mid - 0.25;
        east = mid + 0.25;
      }
      if (north - south < 0.5) {
        final mid = (north + south) / 2;
        south = mid - 0.25;
        north = mid + 0.25;
      }

      params['viewbox'] = '$west,$north,$east,$south';
    }

    final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: params);
    
    debugPrint('[SearchService] Searching Nominatim: $uri');
    
    try {
      final response = await _client.get(uri).timeout(_timeout);
      
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
      
      final List<dynamic> jsonResults = json.decode(response.body);
      final results = jsonResults
          .map((json) => SearchResult.fromNominatim(json as Map<String, dynamic>))
          .toList();
      
      debugPrint('[SearchService] Found ${results.length} results');
      return results;
      
    } catch (e) {
      debugPrint('[SearchService] Search failed: $e');
      throw Exception('Search failed: $e');
    }
  }
}
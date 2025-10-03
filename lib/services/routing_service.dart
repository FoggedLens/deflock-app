import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> waypoints;
  final double distanceMeters;
  final double durationSeconds;
  
  const RouteResult({
    required this.waypoints,
    required this.distanceMeters,
    required this.durationSeconds,
  });
  
  @override
  String toString() {
    return 'RouteResult(waypoints: ${waypoints.length}, distance: ${(distanceMeters/1000).toStringAsFixed(1)}km, duration: ${(durationSeconds/60).toStringAsFixed(1)}min)';
  }
}

class RoutingService {
  static const String _baseUrl = 'https://router.project-osrm.org';
  static const String _userAgent = 'DeFlock/1.0 (OSM surveillance mapping app)';
  static const Duration _timeout = Duration(seconds: 15);
  
  /// Calculate route between two points using OSRM
  Future<RouteResult> calculateRoute({
    required LatLng start,
    required LatLng end,
    String profile = 'driving', // driving, walking, cycling
  }) async {
    debugPrint('[RoutingService] Calculating route from $start to $end');
    
    // OSRM uses lng,lat order (opposite of LatLng)
    final startCoord = '${start.longitude},${start.latitude}';
    final endCoord = '${end.longitude},${end.latitude}';
    
    final uri = Uri.parse('$_baseUrl/route/v1/$profile/$startCoord;$endCoord')
        .replace(queryParameters: {
      'overview': 'full', // Get full geometry
      'geometries': 'polyline', // Use polyline encoding (more compact)
      'steps': 'false', // Don't need turn-by-turn for now
    });
    
    debugPrint('[RoutingService] OSRM request: $uri');
    
    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
        },
      ).timeout(_timeout);
      
      if (response.statusCode != 200) {
        throw RoutingException('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
      
      final data = json.decode(response.body) as Map<String, dynamic>;
      
      // Check OSRM response status
      final code = data['code'] as String?;
      if (code != 'Ok') {
        final message = data['message'] as String? ?? 'Unknown routing error';
        throw RoutingException('OSRM error ($code): $message');
      }
      
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) {
        throw RoutingException('No route found between these points');
      }
      
      final route = routes[0] as Map<String, dynamic>;
      final geometry = route['geometry'] as String?;
      final distance = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final duration = (route['duration'] as num?)?.toDouble() ?? 0.0;
      
      if (geometry == null) {
        throw RoutingException('Route geometry missing from response');
      }
      
      // Decode polyline geometry to waypoints
      final waypoints = _decodePolyline(geometry);
      
      if (waypoints.isEmpty) {
        throw RoutingException('Failed to decode route geometry');
      }
      
      final result = RouteResult(
        waypoints: waypoints,
        distanceMeters: distance,
        durationSeconds: duration,
      );
      
      debugPrint('[RoutingService] Route calculated: $result');
      return result;
      
    } catch (e) {
      debugPrint('[RoutingService] Route calculation failed: $e');
      if (e is RoutingException) {
        rethrow;
      } else {
        throw RoutingException('Network error: $e');
      }
    }
  }
  
  /// Decode OSRM polyline geometry to LatLng waypoints
  List<LatLng> _decodePolyline(String encoded) {
    try {
      final List<LatLng> points = [];
      int index = 0;
      int lat = 0;
      int lng = 0;
      
      while (index < encoded.length) {
        int b;
        int shift = 0;
        int result = 0;
        
        // Decode latitude
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        
        final deltaLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
        lat += deltaLat;
        
        shift = 0;
        result = 0;
        
        // Decode longitude
        do {
          b = encoded.codeUnitAt(index++) - 63;
          result |= (b & 0x1f) << shift;
          shift += 5;
        } while (b >= 0x20);
        
        final deltaLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
        lng += deltaLng;
        
        points.add(LatLng(lat / 1E5, lng / 1E5));
      }
      
      return points;
    } catch (e) {
      debugPrint('[RoutingService] Manual polyline decoding failed: $e');
      return [];
    }
  }
}

class RoutingException implements Exception {
  final String message;
  
  const RoutingException(this.message);
  
  @override
  String toString() => 'RoutingException: $message';
}
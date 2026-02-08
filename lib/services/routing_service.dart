import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import '../dev_config.dart';

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
  static const String _baseUrl = 'https://alprwatch.org/api/v1/deflock/directions';
  static const String _userAgent = 'DeFlock/1.0 (OSM surveillance mapping app)';
  final http.Client _client;

  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  void close() => _client.close();

  // Calculate route between two points using alprwatch
  Future<RouteResult> calculateRoute({
    required LatLng start,
    required LatLng end,
  }) async {
    debugPrint('[RoutingService] Calculating route from $start to $end');

    final prefs = await SharedPreferences.getInstance();
    final avoidanceDistance = prefs.getInt('navigation_avoidance_distance') ?? 250;

    final enabledProfiles = AppState.instance.enabledProfiles.map((p) {
      final full = p.toJson();
      final tags = Map<String, String>.from(full['tags'] as Map);
      tags.removeWhere((key, value) => value.isEmpty);
      return {
        'id': full['id'],
        'name': full['name'],
        'tags': tags,
      };
    }).toList();
    
    final uri = Uri.parse(_baseUrl);
    final params = {
      'start': {
        'longitude': start.longitude,
        'latitude': start.latitude
      },
      'end': {
        'longitude': end.longitude,
        'latitude': end.latitude
      },
      'avoidance_distance': avoidanceDistance,
      'enabled_profiles': enabledProfiles,
      'show_exclusion_zone': false, // for debugging: if true, returns a GeoJSON Feature MultiPolygon showing what areas are avoided in calculating the route
    };
    
    debugPrint('[RoutingService] alprwatch request: $uri $params');
    
    try {
      final response = await _client.post(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Content-Type': 'application/json'
        },
        body: json.encode(params)
      ).timeout(kNavigationRoutingTimeout);

      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[RoutingService] Error response body: ${response.body}');
        } else {
          const maxLen = 500;
          final body = response.body;
          final truncated = body.length > maxLen
              ? '${body.substring(0, maxLen)}… [truncated]'
              : body;
          debugPrint('[RoutingService] Error response body ($maxLen char max): $truncated');
        }
        throw RoutingException('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }
      
      final data = json.decode(response.body) as Map<String, dynamic>;
      debugPrint('[RoutingService] alprwatch response data: $data');
      
      // Check alprwatch response status
      final ok = data['ok'] as bool? ?? false;
      if ( ! ok ) {
        final message = data['error'] as String? ?? 'Unknown routing error';
        throw RoutingException('alprwatch error: $message');
      }
      
      final route = data['result']['route'] as Map<String, dynamic>?;
      if (route == null) {
        throw RoutingException('No route found between these points');
      }
     
      final waypoints = (route['coordinates'] as List<dynamic>?)
        ?.map((inner) {
          final pair = inner as List<dynamic>;
          if (pair.length != 2) return null;
          final lng = (pair[0] as num).toDouble();
          final lat = (pair[1] as num).toDouble();
          return LatLng(lat, lng);
      }).whereType<LatLng>().toList() ?? []; 
      final distance = (route['distance'] as num?)?.toDouble() ?? 0.0;
      final duration = (route['duration'] as num?)?.toDouble() ?? 0.0;
      
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
}

class RoutingException implements Exception {
  final String message;
  
  const RoutingException(this.message);
  
  @override
  String toString() => 'RoutingException: $message';
}

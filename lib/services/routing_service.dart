import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deflock_router_client/api.dart' as router;

import '../app_state.dart';
import '../dev_config.dart';
import 'http_client.dart';

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
  final http.Client _client;

  RoutingService({http.Client? client}) : _client = client ?? UserAgentClient();

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
      final tags = Map<String, String>.from(p.tags);
      tags.removeWhere((key, value) => value.isEmpty);
      return router.NodeProfile(id: p.id, name: p.name, tags: tags);
    }).toList();

    final request = router.DirectionsRequest(
      start: router.Coordinate(latitude: start.latitude, longitude: start.longitude),
      end: router.Coordinate(latitude: end.latitude, longitude: end.longitude),
      avoidanceDistance: avoidanceDistance,
      enabledProfiles: enabledProfiles,
      showExclusionZone: false,
    );

    final uri = Uri.parse(_baseUrl);
    debugPrint('[RoutingService] alprwatch request: $uri ${request.toJson()}');

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json'
        },
        body: json.encode(request.toJson())
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

      final resultData = data['result'] as Map<String, dynamic>?;
      if (resultData == null) {
        throw RoutingException('No result in response');
      }

      final directionsResult = router.DirectionsResult.fromJson(resultData);
      if (directionsResult == null) {
        throw RoutingException('No route found between these points');
      }

      final routeGeometry = directionsResult.route;
      final waypoints = routeGeometry.coordinates.map((pair) {
        return LatLng(pair[1], pair[0]); // [lon, lat] -> LatLng(lat, lon)
      }).toList();

      final result = RouteResult(
        waypoints: waypoints,
        distanceMeters: routeGeometry.distance,
        durationSeconds: routeGeometry.duration,
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

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';
import 'http_client.dart';
import 'service_policy.dart';

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
  static const String defaultUrl = 'https://api.dontgetflocked.com/api/v1/deflock/directions';
  static const String fallbackUrl = 'https://alprwatch.org/api/v1/deflock/directions';
  static const _policy = ResiliencePolicy(
    maxRetries: 1,
    httpTimeout: Duration(seconds: 30),
  );

  final http.Client _client;
  /// Optional override URL. When null, uses defaultUrl (or settings override).
  final String? _baseUrlOverride;

  RoutingService({http.Client? client, String? baseUrl})
      : _client = client ?? UserAgentClient(),
        _baseUrlOverride = baseUrl;

  void close() => _client.close();

  /// Resolve the primary URL to use: constructor override or default.
  String get _primaryUrl => _baseUrlOverride ?? defaultUrl;

  // Calculate route between two points
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
      'show_exclusion_zone': false,
    };

    // Snapshot the URL once so fallback decision is consistent
    final primaryUrl = _primaryUrl;
    final canFallback = primaryUrl == defaultUrl;

    return executeWithFallback<RouteResult>(
      primaryUrl: primaryUrl,
      fallbackUrl: canFallback ? fallbackUrl : null,
      execute: (url) => _postRoute(url, params),
      classifyError: _classifyError,
      policy: _policy,
    );
  }

  Future<RouteResult> _postRoute(String url, Map<String, dynamic> params) async {
    final uri = Uri.parse(url);
    debugPrint('[RoutingService] POST $uri');

    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json'
        },
        body: json.encode(params)
      ).timeout(_policy.httpTimeout);

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
        throw RoutingException('HTTP ${response.statusCode}: ${response.reasonPhrase}',
            statusCode: response.statusCode);
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      debugPrint('[RoutingService] response data: $data');

      // Check response status
      final ok = data['ok'] as bool? ?? false;
      if ( ! ok ) {
        final message = data['error'] as String? ?? 'Unknown routing error';
        throw RoutingException('API error: $message', isApiError: true);
      }

      final route = data['result']['route'] as Map<String, dynamic>?;
      if (route == null) {
        throw RoutingException('No route found between these points', isApiError: true);
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

  static ErrorDisposition _classifyError(Object error) {
    if (error is! RoutingException) return ErrorDisposition.retry;
    if (error.isApiError) return ErrorDisposition.abort;
    final status = error.statusCode;
    if (status != null && status >= 400 && status < 500) {
      if (status == 429) return ErrorDisposition.fallback;
      return ErrorDisposition.abort;
    }
    return ErrorDisposition.retry;
  }
}

class RoutingException implements Exception {
  final String message;
  final int? statusCode;
  final bool isApiError;

  const RoutingException(this.message, {this.statusCode, this.isApiError = false});

  @override
  String toString() => 'RoutingException: $message';
}

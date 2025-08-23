import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'map_data_provider.dart';

/// Simple HTTP client that routes tile requests through the centralized MapDataProvider.
/// This ensures all tile fetching (offline/online routing, retries, etc.) is in one place.
class SimpleTileHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final MapDataProvider _mapDataProvider = MapDataProvider();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Only intercept tile requests to OSM
    if (request.url.host == 'tile.openstreetmap.org') {
      return _handleTileRequest(request);
    }
    
    // Pass through all other requests
    return _inner.send(request);
  }

  Future<http.StreamedResponse> _handleTileRequest(http.BaseRequest request) async {
    final pathSegments = request.url.pathSegments;
    
    // Parse z/x/y from URL like: /15/5242/12666.png
    if (pathSegments.length == 3) {
      final z = int.tryParse(pathSegments[0]);
      final x = int.tryParse(pathSegments[1]);
      final yPng = pathSegments[2];
      final y = int.tryParse(yPng.replaceAll('.png', ''));
      
      if (z != null && x != null && y != null) {
        return _getTile(z, x, y);
      }
    }
    
    // Malformed tile URL - pass through to OSM
    return _inner.send(request);
  }

  Future<http.StreamedResponse> _getTile(int z, int x, int y) async {
    // Only serve from offline if available - otherwise let flutter_map handle directly
    try {
      // Check if we have this tile offline (without fetching)
      final localTileBytes = await _mapDataProvider.getTile(z: z, x: x, y: y, source: MapSource.local);
      
      debugPrint('[SimpleTileService] Serving tile $z/$x/$y from offline storage');
      
      // Serve offline tile with proper cache headers
      return http.StreamedResponse(
        Stream.value(localTileBytes),
        200,
        headers: {
          'Content-Type': 'image/png',
          'Cache-Control': 'public, max-age=604800',
          'Expires': _httpDateFormat(DateTime.now().add(Duration(days: 7))),
          'Last-Modified': _httpDateFormat(DateTime.now().subtract(Duration(hours: 1))),
        },
      );
      
    } catch (e) {
      // No offline tile - try OSM with proper error handling
      debugPrint('[SimpleTileService] No offline tile for $z/$x/$y - trying OSM');
      try {
        return await _inner.send(http.Request('GET', Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png')));
      } catch (networkError) {
        debugPrint('[SimpleTileService] OSM request failed for $z/$x/$y: $networkError');
        // Return 404 instead of throwing - let flutter_map handle gracefully
        return http.StreamedResponse(
          Stream.value(<int>[]),
          404,
          reasonPhrase: 'Network tile unavailable: $networkError',
        );
      }
    }
  }

  /// Clear any queued tile requests when map view changes
  void clearTileQueue() {
    _mapDataProvider.clearTileQueue();
  }

  /// Format date for HTTP headers (RFC 7231)
  String _httpDateFormat(DateTime date) {
    final utc = date.toUtc();
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                   'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final weekday = weekdays[utc.weekday - 1];
    final day = utc.day.toString().padLeft(2, '0');
    final month = months[utc.month - 1];
    final year = utc.year;
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    
    return '$weekday, $day $month $year $hour:$minute:$second GMT';
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
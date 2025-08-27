import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../app_state.dart';
import 'map_data_provider.dart';
import 'network_status.dart';

/// Simple HTTP client that routes tile requests through the centralized MapDataProvider.
/// This ensures all tile fetching (offline/online routing, retries, etc.) is in one place.
class SimpleTileHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final MapDataProvider _mapDataProvider = MapDataProvider();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // Extract tile coordinates from our custom URL scheme
    final tileCoords = _extractTileCoords(request.url);
    if (tileCoords != null) {
      final z = tileCoords['z']!;
      final x = tileCoords['x']!;
      final y = tileCoords['y']!;
      return _handleTileRequest(z, x, y);
    }
    
    // Pass through non-tile requests
    return _inner.send(request);
  }

  /// Extract z/x/y coordinates from our fake domain: https://tiles.local/provider/type/z/x/y
  /// We ignore the provider/type in the URL since we use current AppState for actual fetching
  Map<String, int>? _extractTileCoords(Uri url) {
    if (url.host != 'tiles.local') return null;
    
    final pathSegments = url.pathSegments;
    if (pathSegments.length != 5) return null;
    
    // pathSegments[0] = providerId (for cache separation only)
    // pathSegments[1] = tileTypeId (for cache separation only) 
    final z = int.tryParse(pathSegments[2]);
    final x = int.tryParse(pathSegments[3]);
    final y = int.tryParse(pathSegments[4]);
    
    if (z != null && x != null && y != null) {
      return {'z': z, 'x': x, 'y': y};
    }
    
    return null;
  }

  Future<http.StreamedResponse> _handleTileRequest(int z, int x, int y) async {
    try {
      // Always go through MapDataProvider - it handles offline/online routing
      // MapDataProvider will get current provider from AppState
      final tileBytes = await _mapDataProvider.getTile(z: z, x: x, y: y, source: MapSource.auto);
      
      // Show success status briefly
      NetworkStatus.instance.setSuccess();
      
      // Serve tile with proper cache headers
      return http.StreamedResponse(
        Stream.value(tileBytes),
        200,
        headers: {
          'Content-Type': 'image/png',
          'Cache-Control': 'public, max-age=604800',
          'Expires': _httpDateFormat(DateTime.now().add(Duration(days: 7))),
          'Last-Modified': _httpDateFormat(DateTime.now().subtract(Duration(hours: 1))),
        },
      );
      
    } catch (e) {
      debugPrint('[SimpleTileService] Could not get tile $z/$x/$y: $e');
      
      // 404 means no tiles available - show "no data" status briefly
      NetworkStatus.instance.setNoData();
      
      // Return 404 and let flutter_map handle it gracefully
      return http.StreamedResponse(
        Stream.value(<int>[]),
        404,
        reasonPhrase: 'Tile unavailable: $e',
      );
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
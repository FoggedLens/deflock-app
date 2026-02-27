import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

import '../models/search_result.dart';
import 'http_client.dart';
import 'service_policy.dart';

/// Cached search result with expiry.
class _CachedResult {
  final List<SearchResult> results;
  final DateTime cachedAt;

  _CachedResult(this.results) : cachedAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(cachedAt) > const Duration(minutes: 5);
}

class SearchService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const int _maxResults = 5;
  static const Duration _timeout = Duration(seconds: 10);
  final _client = UserAgentClient();

  /// Client-side result cache, keyed by normalized query + viewbox.
  /// Required by Nominatim usage policy. Static so all SearchService
  /// instances share the cache and don't generate redundant requests.
  static final Map<String, _CachedResult> _resultCache = {};


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

  /// Search using Nominatim API with rate limiting and result caching.
  ///
  /// Nominatim usage policy requires:
  /// - Max 1 request per second
  /// - Client-side result caching
  /// - No auto-complete / typeahead
  Future<List<SearchResult>> _searchNominatim(String query, {LatLngBounds? viewbox}) async {
    final cacheKey = _buildCacheKey(query, viewbox);

    // Check cache first (Nominatim policy requires client-side caching)
    final cached = _resultCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      debugPrint('[SearchService] Cache hit for "$query"');
      return cached.results;
    }

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

    // Rate limit: max 1 request/sec per Nominatim policy
    await ServiceRateLimiter.acquire(ServiceType.nominatim);
    try {
      final response = await _client.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}');
      }

      final List<dynamic> jsonResults = json.decode(response.body);
      final results = jsonResults
          .map((json) => SearchResult.fromNominatim(json as Map<String, dynamic>))
          .toList();

      // Cache the results
      _resultCache[cacheKey] = _CachedResult(results);
      _pruneCache();

      debugPrint('[SearchService] Found ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('[SearchService] Search failed: $e');
      throw Exception('Search failed: $e');
    } finally {
      ServiceRateLimiter.release(ServiceType.nominatim);
    }
  }

  /// Build a cache key from the query and viewbox.
  String _buildCacheKey(String query, LatLngBounds? viewbox) {
    final normalizedQuery = query.trim().toLowerCase();
    if (viewbox == null) return normalizedQuery;
    // Round viewbox to 1 decimal place to group nearby viewboxes
    double round1(double v) => (v * 10).round() / 10;
    return '$normalizedQuery|${round1(viewbox.west)},${round1(viewbox.south)},${round1(viewbox.east)},${round1(viewbox.north)}';
  }

  /// Remove expired entries and limit cache size.
  void _pruneCache() {
    _resultCache.removeWhere((_, cached) => cached.isExpired);
    // Limit cache to 50 entries to prevent unbounded growth
    if (_resultCache.length > 50) {
      final sortedKeys = _resultCache.keys.toList()
        ..sort((a, b) => _resultCache[a]!.cachedAt.compareTo(_resultCache[b]!.cachedAt));
      for (final key in sortedKeys.take(_resultCache.length - 50)) {
        _resultCache.remove(key);
      }
    }
  }
}

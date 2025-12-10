import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart';

/// Service for fetching tag value suggestions from OpenStreetMap Name Suggestion Index
class NSIService {
  static final NSIService _instance = NSIService._();
  factory NSIService() => _instance;
  NSIService._();

  static const String _userAgent = 'DeFlock/2.1.0 (OSM surveillance mapping app)';
  static const Duration _timeout = Duration(seconds: 10);
  
  // Cache to avoid repeated API calls
  final Map<String, List<String>> _suggestionCache = {};

  /// Get suggested values for a given OSM tag key
  /// Returns a list of the most commonly used values, or empty list if none found
  Future<List<String>> getSuggestionsForTag(String tagKey) async {
    if (tagKey.trim().isEmpty) {
      return [];
    }

    final cacheKey = tagKey.trim().toLowerCase();
    
    // Return cached results if available
    if (_suggestionCache.containsKey(cacheKey)) {
      return _suggestionCache[cacheKey]!;
    }

    try {
      final suggestions = await _fetchSuggestionsForTag(tagKey);
      _suggestionCache[cacheKey] = suggestions;
      return suggestions;
    } catch (e) {
      debugPrint('[NSIService] Failed to fetch suggestions for $tagKey: $e');
      // Cache empty result to avoid repeated failures
      _suggestionCache[cacheKey] = [];
      return [];
    }
  }

  /// Fetch tag value suggestions from TagInfo API
  Future<List<String>> _fetchSuggestionsForTag(String tagKey) async {
    final uri = Uri.parse('https://taginfo.openstreetmap.org/api/4/key/values')
        .replace(queryParameters: {
      'key': tagKey,
      'format': 'json',
      'sortname': 'count',
      'sortorder': 'desc',
      'page': '1',
      'rp': '15', // Get top 15 most commonly used values
    });

    final response = await http.get(
      uri,
      headers: {'User-Agent': _userAgent},
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('TagInfo API returned status ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final values = data['data'] as List<dynamic>? ?? [];
    
    // Extract the most commonly used values
    final suggestions = <String>[];
    
    for (final item in values) {
      if (item is Map<String, dynamic>) {
        final value = item['value'] as String?;
        if (value != null && value.trim().isNotEmpty && _isValidSuggestion(value)) {
          suggestions.add(value.trim());
        }
      }
      
      // Limit to top 10 suggestions for UI performance
      if (suggestions.length >= 10) break;
    }
    
    return suggestions;
  }

  /// Filter out common unwanted values that appear in TagInfo but aren't useful suggestions
  bool _isValidSuggestion(String value) {
    final lowercaseValue = value.toLowerCase();
    
    // Filter out obvious non-useful values
    final unwanted = {
      'yes', 'no', 'unknown', '?', 'null', 'none', 'n/a', 'na', 
      'todo', 'fixme', 'check', 'verify', 'test', 'temp', 'temporary'
    };
    
    if (unwanted.contains(lowercaseValue)) {
      return false;
    }
    
    // Filter out very short generic values (except single letters that might be valid)
    if (value.length == 1 && !RegExp(r'[A-Z]').hasMatch(value)) {
      return false;
    }
    
    return true;
  }



  /// Get suggestions for a tag key - returns empty list when offline mode enabled
  Future<List<String>> getAllSuggestions(String tagKey) async {
    // Check if app is in offline mode
    if (AppState.instance.offlineMode) {
      debugPrint('[NSIService] Offline mode enabled - no suggestions available for $tagKey');
      return []; // No suggestions when in offline mode - user must input manually
    }
    
    // Online mode: try to get suggestions from API
    try {
      return await getSuggestionsForTag(tagKey);
    } catch (e) {
      debugPrint('[NSIService] API call failed: $e');
      return []; // No fallback - just return empty list
    }
  }

  /// Clear the suggestion cache (useful for testing or memory management)
  void clearCache() {
    _suggestionCache.clear();
  }
}
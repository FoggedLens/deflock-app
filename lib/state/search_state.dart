import 'package:flutter/material.dart';

import '../models/search_result.dart';
import '../services/search_service.dart';

class SearchState extends ChangeNotifier {
  final SearchService _searchService = SearchService();
  
  bool _isLoading = false;
  List<SearchResult> _results = [];
  String _lastQuery = '';
  
  // Getters
  bool get isLoading => _isLoading;
  List<SearchResult> get results => List.unmodifiable(_results);
  String get lastQuery => _lastQuery;
  
  /// Search for places by query string
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      _clearResults();
      return;
    }
    
    // Don't search if query hasn't changed
    if (query.trim() == _lastQuery.trim()) {
      return;
    }
    
    _setLoading(true);
    _lastQuery = query.trim();
    
    try {
      final results = await _searchService.search(query.trim());
      _results = results;
      debugPrint('[SearchState] Found ${results.length} results for "$query"');
    } catch (e) {
      debugPrint('[SearchState] Search failed: $e');
      _results = [];
    }
    
    _setLoading(false);
  }
  
  /// Clear search results
  void clearResults() {
    _clearResults();
  }
  
  void _clearResults() {
    if (_results.isNotEmpty || _lastQuery.isNotEmpty) {
      _results = [];
      _lastQuery = '';
      notifyListeners();
    }
  }
  
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }
}
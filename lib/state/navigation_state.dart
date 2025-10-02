import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/search_result.dart';
import '../services/search_service.dart';

/// Simplified navigation modes - brutalist approach
enum AppNavigationMode {
  normal,      // Regular map view
  search,      // Search/routing UI active  
  routeActive, // Following a route
}

/// Simplified navigation state - fewer modes, clearer logic
class NavigationState extends ChangeNotifier {
  final SearchService _searchService = SearchService();
  
  // Core state - just 3 modes
  AppNavigationMode _mode = AppNavigationMode.normal;
  
  // Simple flags instead of complex sub-states
  bool _isSettingSecondPoint = false;
  bool _isCalculating = false;
  bool _showingOverview = false;
  
  // Search state
  bool _isSearchLoading = false;
  List<SearchResult> _searchResults = [];
  String _lastQuery = '';
  
  // Location state
  LatLng? _provisionalPinLocation;
  String? _provisionalPinAddress;
  
  // Route state
  LatLng? _routeStart;
  LatLng? _routeEnd;
  String? _routeStartAddress;
  String? _routeEndAddress;
  List<LatLng>? _routePath;
  double? _routeDistance;
  bool _nextPointIsStart = false; // What we're setting next
  
  // Getters
  AppNavigationMode get mode => _mode;
  bool get isSettingSecondPoint => _isSettingSecondPoint;
  bool get isCalculating => _isCalculating;
  bool get showingOverview => _showingOverview;
  
  bool get isSearchLoading => _isSearchLoading;
  List<SearchResult> get searchResults => List.unmodifiable(_searchResults);
  String get lastQuery => _lastQuery;
  
  LatLng? get provisionalPinLocation => _provisionalPinLocation;
  String? get provisionalPinAddress => _provisionalPinAddress;
  
  LatLng? get routeStart => _routeStart;
  LatLng? get routeEnd => _routeEnd;
  String? get routeStartAddress => _routeStartAddress;
  String? get routeEndAddress => _routeEndAddress;
  List<LatLng>? get routePath => _routePath != null ? List.unmodifiable(_routePath!) : null;
  double? get routeDistance => _routeDistance;
  bool get settingRouteStart => _nextPointIsStart; // For sheet display compatibility
  
  // Simplified convenience getters
  bool get isInSearchMode => _mode == AppNavigationMode.search;
  bool get isInRouteMode => _mode == AppNavigationMode.routeActive;
  bool get hasActiveRoute => _routePath != null && _mode == AppNavigationMode.routeActive;
  bool get showProvisionalPin => _provisionalPinLocation != null && (_mode == AppNavigationMode.search);
  bool get showSearchButton => _mode == AppNavigationMode.normal;
  bool get showRouteButton => _mode == AppNavigationMode.routeActive;
  
  /// BRUTALIST: Single entry point to search mode
  void enterSearchMode(LatLng mapCenter) {
    debugPrint('[NavigationState] enterSearchMode - current mode: $_mode');
    
    if (_mode != AppNavigationMode.normal) {
      debugPrint('[NavigationState] Cannot enter search mode - not in normal mode');
      return;
    }
    
    _mode = AppNavigationMode.search;
    _provisionalPinLocation = mapCenter;
    _provisionalPinAddress = null;
    _clearSearchResults();
    
    debugPrint('[NavigationState] Entered search mode');
    notifyListeners();
  }
  
  /// BRUTALIST: Single cancellation method - cleans up EVERYTHING
  void cancel() {
    debugPrint('[NavigationState] cancel() - cleaning up all state');
    
    _mode = AppNavigationMode.normal;
    
    // Clear ALL provisional data
    _provisionalPinLocation = null;
    _provisionalPinAddress = null;
    
    // Clear ALL route data (except active route)
    if (_mode != AppNavigationMode.routeActive) {
      _routeStart = null;
      _routeEnd = null;
      _routeStartAddress = null;
      _routeEndAddress = null;
      _routePath = null;
      _routeDistance = null;
    }
    
    // Reset ALL flags
    _isSettingSecondPoint = false;
    _isCalculating = false;
    _showingOverview = false;
    _nextPointIsStart = false;
    
    // Clear search
    _clearSearchResults();
    
    debugPrint('[NavigationState] Everything cleaned up');
    notifyListeners();
  }
  
  /// Update provisional pin when map moves
  void updateProvisionalPinLocation(LatLng newLocation) {
    if (!showProvisionalPin) return;
    
    _provisionalPinLocation = newLocation;
    _provisionalPinAddress = null; // Clear address when location changes
    notifyListeners();
  }
  
  /// Jump to search result
  void selectSearchResult(SearchResult result) {
    if (_mode != AppNavigationMode.search) return;
    
    _provisionalPinLocation = result.coordinates;
    _provisionalPinAddress = result.displayName;
    _clearSearchResults();
    
    debugPrint('[NavigationState] Selected search result: ${result.displayName}');
    notifyListeners();
  }
  
  /// Start route planning - simplified logic
  void startRoutePlanning({required bool thisLocationIsStart}) {
    if (_mode != AppNavigationMode.search || _provisionalPinLocation == null) return;
    
    debugPrint('[NavigationState] Starting route planning - thisLocationIsStart: $thisLocationIsStart');
    
    // Clear any previous route data
    _routeStart = null;
    _routeEnd = null;
    _routeStartAddress = null;
    _routeEndAddress = null;
    _routePath = null;
    _routeDistance = null;
    
    // Set the current location as start or end
    if (thisLocationIsStart) {
      _routeStart = _provisionalPinLocation;
      _routeStartAddress = _provisionalPinAddress;
      _nextPointIsStart = false; // Next we'll set the END
      debugPrint('[NavigationState] Set route start, next setting END');
    } else {
      _routeEnd = _provisionalPinLocation;
      _routeEndAddress = _provisionalPinAddress;
      _nextPointIsStart = true; // Next we'll set the START
      debugPrint('[NavigationState] Set route end, next setting START');
    }
    
    // Enter second point selection mode
    _isSettingSecondPoint = true;
    notifyListeners();
  }
  
  /// Select the second route point
  void selectSecondRoutePoint() {
    if (!_isSettingSecondPoint || _provisionalPinLocation == null) return;
    
    debugPrint('[NavigationState] Selecting second route point - nextPointIsStart: $_nextPointIsStart');
    
    // Set the second point
    if (_nextPointIsStart) {
      _routeStart = _provisionalPinLocation;
      _routeStartAddress = _provisionalPinAddress;
    } else {
      _routeEnd = _provisionalPinLocation;
      _routeEndAddress = _provisionalPinAddress;
    }
    
    _isSettingSecondPoint = false;
    _calculateRoute();
  }
  
  /// Calculate route
  void _calculateRoute() {
    if (_routeStart == null || _routeEnd == null) return;
    
    debugPrint('[NavigationState] Calculating route...');
    _isCalculating = true;
    notifyListeners();
    
    // Mock route calculation
    Future.delayed(const Duration(seconds: 1), () {
      if (!_isCalculating) return; // Canceled
      
      _routePath = [_routeStart!, _routeEnd!];
      _routeDistance = const Distance().as(LengthUnit.Meter, _routeStart!, _routeEnd!);
      _isCalculating = false;
      _showingOverview = true;
      _provisionalPinLocation = null; // Hide provisional pin
      
      debugPrint('[NavigationState] Route calculated: ${(_routeDistance! / 1000).toStringAsFixed(1)} km');
      notifyListeners();
    });
  }
  
  /// Start following the route
  void startRoute() {
    if (_routePath == null) return;
    
    _mode = AppNavigationMode.routeActive;
    _showingOverview = false;
    
    debugPrint('[NavigationState] Started following route');
    notifyListeners();
  }
  
  /// Show route overview (from route button during active navigation)
  void showRouteOverview() {
    if (_mode != AppNavigationMode.routeActive) return;
    
    _showingOverview = true;
    debugPrint('[NavigationState] Showing route overview');
    notifyListeners();
  }
  
  /// Hide route overview (back to active navigation)
  void hideRouteOverview() {
    if (_mode != AppNavigationMode.routeActive) return;
    
    _showingOverview = false;
    debugPrint('[NavigationState] Hiding route overview');
    notifyListeners();
  }
  
  /// Cancel active route and return to normal
  void cancelRoute() {
    if (_mode != AppNavigationMode.routeActive) return;
    
    debugPrint('[NavigationState] Canceling active route');
    cancel(); // Use the brutalist single cleanup method
  }
  
  /// Search functionality
  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      _clearSearchResults();
      return;
    }
    
    if (query.trim() == _lastQuery.trim()) return;
    
    _setSearchLoading(true);
    _lastQuery = query.trim();
    
    try {
      final results = await _searchService.search(query.trim());
      _searchResults = results;
      debugPrint('[NavigationState] Found ${results.length} results');
    } catch (e) {
      debugPrint('[NavigationState] Search failed: $e');
      _searchResults = [];
    }
    
    _setSearchLoading(false);
  }
  
  void clearSearchResults() {
    _clearSearchResults();
  }
  
  void _clearSearchResults() {
    if (_searchResults.isNotEmpty || _lastQuery.isNotEmpty) {
      _searchResults = [];
      _lastQuery = '';
      notifyListeners();
    }
  }
  
  void _setSearchLoading(bool loading) {
    if (_isSearchLoading != loading) {
      _isSearchLoading = loading;
      notifyListeners();
    }
  }
}
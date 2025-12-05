import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/search_result.dart';
import '../services/search_service.dart';
import '../services/routing_service.dart';
import '../dev_config.dart';

/// Simplified navigation modes - brutalist approach
enum AppNavigationMode {
  normal,      // Regular map view
  search,      // Search/routing UI active  
  routeActive, // Following a route
}

/// Simplified navigation state - fewer modes, clearer logic
class NavigationState extends ChangeNotifier {
  final SearchService _searchService = SearchService();
  final RoutingService _routingService = RoutingService();
  
  // Core state - just 3 modes
  AppNavigationMode _mode = AppNavigationMode.normal;
  
  // Simple flags instead of complex sub-states
  bool _isSettingSecondPoint = false;
  bool _isCalculating = false;
  bool _showingOverview = false;
  String? _routingError;
  
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
  String? get routingError => _routingError;
  bool get hasRoutingError => _routingError != null;
  
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
  
  /// Check if the start and end locations are too close together
  bool get areRoutePointsTooClose {
    if (!_isSettingSecondPoint || _provisionalPinLocation == null) return false;
    
    final firstPoint = _nextPointIsStart ? _routeEnd : _routeStart;
    if (firstPoint == null) return false;
    
    final distance = const Distance().as(LengthUnit.Meter, firstPoint, _provisionalPinLocation!);
    return distance < kNavigationMinRouteDistance;
  }
  
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
    _routingError = null;
    
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
    
    // BRUTALIST FIX: Set calculating state BEFORE clearing isSettingSecondPoint
    // to prevent UI from briefly showing route buttons again
    _isSettingSecondPoint = false;
    _isCalculating = true;
    _routingError = null; // Clear any previous errors
    
    // Notify listeners immediately to update UI before async calculation starts
    notifyListeners();
    
    _calculateRoute();
  }
  
  /// Retry route calculation (for error recovery)
  void retryRouteCalculation() {
    if (_routeStart == null || _routeEnd == null) return;
    
    debugPrint('[NavigationState] Retrying route calculation');
    _routingError = null;
    _calculateRoute();
  }
  
  /// Calculate route using alprwatch
  void _calculateRoute() {
    if (_routeStart == null || _routeEnd == null) return;

    debugPrint('[NavigationState] Calculating route with alprwatch...');
    _isCalculating = true;
    _routingError = null;
    notifyListeners();
    
    _routingService.calculateRoute(
      start: _routeStart!,
      end: _routeEnd!,
    ).then((routeResult) {
      if (!_isCalculating) return; // Canceled while calculating
      
      _routePath = routeResult.waypoints;
      _routeDistance = routeResult.distanceMeters;
      _isCalculating = false;
      _showingOverview = true;
      _provisionalPinLocation = null; // Hide provisional pin
      
      debugPrint('[NavigationState] alprwatch route calculated: ${routeResult.toString()}');
      notifyListeners();
      
    }).catchError((error) {
      if (!_isCalculating) return; // Canceled while calculating
      
      debugPrint('[NavigationState] Route calculation failed: $error');
      _isCalculating = false;
      _routingError = error.toString().replaceAll('RoutingException: ', '');
      
      // Don't show overview on error, stay in current state
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
  
  /// Check if user should auto-enable follow-me (called from outside with user location)
  bool shouldAutoEnableFollowMe(LatLng? userLocation) {
    if (userLocation == null || _routeStart == null) return false;
    
    final distanceToStart = const Distance().as(LengthUnit.Meter, userLocation, _routeStart!);
    final shouldEnable = distanceToStart <= 1000; // Within 1km
    
    debugPrint('[NavigationState] Distance to start: ${distanceToStart.toStringAsFixed(0)}m, auto follow-me: $shouldEnable');
    return shouldEnable;
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

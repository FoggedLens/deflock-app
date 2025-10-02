import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/search_result.dart';
import '../services/search_service.dart';

/// Navigation modes for routing and search functionality
enum AppNavigationMode {
  normal,           // Default state - normal map view
  search,           // Search box visible, provisional pin active
  searchInput,      // Keyboard open, UI elements hidden
  routeSetup,       // Placing second pin for routing
  routeCalculating, // Computing route with loading indicator
  routePreview,     // Route ready, showing start/cancel options
  routeActive,      // Following an active route
  routeOverview,    // Viewing active route overview
}

/// Manages all navigation, search, and routing state
class NavigationState extends ChangeNotifier {
  final SearchService _searchService = SearchService();
  
  AppNavigationMode _mode = AppNavigationMode.normal;
  
  // Search state
  bool _isSearchLoading = false;
  List<SearchResult> _searchResults = [];
  String _lastQuery = '';
  List<String> _searchHistory = [];
  
  // Provisional pin state (for route planning)
  LatLng? _provisionalPinLocation;
  String? _provisionalPinAddress;
  
  // Route state
  LatLng? _routeStart;
  LatLng? _routeEnd;
  String? _routeStartAddress;
  String? _routeEndAddress;
  List<LatLng>? _routePath;
  double? _routeDistance;
  bool _settingRouteStart = true; // true = setting start, false = setting end
  
  // Getters
  AppNavigationMode get mode => _mode;
  bool get isSearchLoading => _isSearchLoading;
  List<SearchResult> get searchResults => List.unmodifiable(_searchResults);
  String get lastQuery => _lastQuery;
  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  
  LatLng? get provisionalPinLocation => _provisionalPinLocation;
  String? get provisionalPinAddress => _provisionalPinAddress;
  
  LatLng? get routeStart => _routeStart;
  LatLng? get routeEnd => _routeEnd;
  String? get routeStartAddress => _routeStartAddress;
  String? get routeEndAddress => _routeEndAddress;
  List<LatLng>? get routePath => _routePath != null ? List.unmodifiable(_routePath!) : null;
  double? get routeDistance => _routeDistance;
  bool get settingRouteStart => _settingRouteStart;
  
  // Convenience getters
  bool get isInSearchMode => _mode == AppNavigationMode.search || _mode == AppNavigationMode.searchInput;
  bool get isInRouteMode => _mode == AppNavigationMode.routeSetup || 
                           _mode == AppNavigationMode.routeCalculating ||
                           _mode == AppNavigationMode.routePreview ||
                           _mode == AppNavigationMode.routeActive ||
                           _mode == AppNavigationMode.routeOverview;
  bool get hasActiveRoute => _routePath != null;
  bool get showProvisionalPin => _provisionalPinLocation != null && 
                                (_mode == AppNavigationMode.search || 
                                 _mode == AppNavigationMode.routeSetup);
  
  /// Enter search mode with provisional pin at current map center
  void enterSearchMode(LatLng mapCenter) {
    debugPrint('[NavigationState] enterSearchMode called - current mode: $_mode, mapCenter: $mapCenter');
    
    if (_mode != AppNavigationMode.normal) {
      debugPrint('[NavigationState] Cannot enter search mode - current mode is $_mode (not normal)');
      return;
    }
    
    _mode = AppNavigationMode.search;
    _provisionalPinLocation = mapCenter;
    _provisionalPinAddress = null;
    _clearSearchResults();
    debugPrint('[NavigationState] Entered search mode at $mapCenter');
    notifyListeners();
  }
  
  /// Enter search input mode (keyboard open)
  void enterSearchInputMode() {
    if (_mode != AppNavigationMode.search) return;
    
    _mode = AppNavigationMode.searchInput;
    debugPrint('[NavigationState] Entered search input mode');
    notifyListeners();
  }
  
  /// Exit search input mode back to search
  void exitSearchInputMode() {
    if (_mode != AppNavigationMode.searchInput) return;
    
    _mode = AppNavigationMode.search;
    debugPrint('[NavigationState] Exited search input mode');
    notifyListeners();
  }
  
  /// Cancel search mode and return to normal
  void cancelSearchMode() {
    debugPrint('[NavigationState] cancelSearchMode called - mode: $_mode, isInSearch: $isInSearchMode, isInRoute: $isInRouteMode');
    
    if (!isInSearchMode && _mode != AppNavigationMode.routeSetup) return;
    
    _mode = AppNavigationMode.normal;
    _provisionalPinLocation = null;
    _provisionalPinAddress = null;
    _clearSearchResults();
    
    // Clear ALL route data when canceling
    _routeStart = null;
    _routeEnd = null;
    _routeStartAddress = null;
    _routeEndAddress = null;
    _routePath = null;
    _routeDistance = null;
    _settingRouteStart = true;
    
    debugPrint('[NavigationState] Cancelled search mode - cleaned up all data');
    notifyListeners();
  }
  
  /// Update provisional pin location (when map moves during search)
  void updateProvisionalPinLocation(LatLng newLocation) {
    if (!showProvisionalPin) return;
    
    _provisionalPinLocation = newLocation;
    // Clear address since location changed
    _provisionalPinAddress = null;
    notifyListeners();
  }
  
  /// Jump to search result and update provisional pin
  void selectSearchResult(SearchResult result) {
    if (!isInSearchMode) return;
    
    _provisionalPinLocation = result.coordinates;
    _provisionalPinAddress = result.displayName;
    _mode = AppNavigationMode.search; // Exit search input mode
    _clearSearchResults();
    debugPrint('[NavigationState] Selected search result: ${result.displayName}');
    notifyListeners();
  }
  
  /// Start route setup (user clicked "route to" or "route from")
  void startRouteSetup({required bool settingStart}) {
    debugPrint('[NavigationState] startRouteSetup called - settingStart: $settingStart, mode: $_mode, location: $_provisionalPinLocation');
    
    if (_mode != AppNavigationMode.search || _provisionalPinLocation == null) {
      debugPrint('[NavigationState] startRouteSetup - early return');
      return;
    }
    
    // Clear any previous route data
    _routeStart = null;
    _routeEnd = null;
    _routeStartAddress = null;
    _routeEndAddress = null;
    _routePath = null;
    _routeDistance = null;
    
    if (settingStart) {
      // "Route From" - this location is the START, now we need to pick END
      _routeStart = _provisionalPinLocation;
      _routeStartAddress = _provisionalPinAddress;
      _settingRouteStart = false; // Next, we'll be setting the END
      debugPrint('[NavigationState] Set route start: $_routeStart, next will set END');
    } else {
      // "Route To" - this location is the END, now we need to pick START  
      _routeEnd = _provisionalPinLocation;
      _routeEndAddress = _provisionalPinAddress;
      _settingRouteStart = true; // Next, we'll be setting the START
      debugPrint('[NavigationState] Set route end: $_routeEnd, next will set START');
    }
    
    _mode = AppNavigationMode.routeSetup;
    // Keep provisional pin active for second location
    debugPrint('[NavigationState] Started route setup (setting ${settingStart ? 'start' : 'end'})');
    notifyListeners();
  }
  
  /// Lock in second route location
  void selectRouteLocation() {
    debugPrint('[NavigationState] selectRouteLocation called - mode: $_mode, provisional: $_provisionalPinLocation');
    
    if (_mode != AppNavigationMode.routeSetup || _provisionalPinLocation == null) {
      debugPrint('[NavigationState] selectRouteLocation - early return (mode: $_mode, location: $_provisionalPinLocation)');
      return;
    }
    
    if (_settingRouteStart) {
      _routeStart = _provisionalPinLocation;
      _routeStartAddress = _provisionalPinAddress;
      debugPrint('[NavigationState] Set route start: $_routeStart');
    } else {
      _routeEnd = _provisionalPinLocation;
      _routeEndAddress = _provisionalPinAddress;
      debugPrint('[NavigationState] Set route end: $_routeEnd');
    }
    
    debugPrint('[NavigationState] Route points - start: $_routeStart, end: $_routeEnd');
    
    // Start route calculation
    _calculateRoute();
  }
  
  /// Calculate route (mock implementation for now)
  void _calculateRoute() {
    if (_routeStart == null || _routeEnd == null) return;
    
    _mode = AppNavigationMode.routeCalculating;
    notifyListeners();
    
    // Mock route calculation with delay
    Future.delayed(const Duration(seconds: 2), () {
      if (_mode != AppNavigationMode.routeCalculating) return;
      
      // Create simple straight line route for now
      _routePath = [_routeStart!, _routeEnd!];
      _routeDistance = const Distance().as(LengthUnit.Meter, _routeStart!, _routeEnd!);
      
      _mode = AppNavigationMode.routePreview;
      _provisionalPinLocation = null; // Hide provisional pin
      debugPrint('[NavigationState] Route calculated: ${_routeDistance! / 1000.0} km');
      notifyListeners();
    });
  }
  
  /// Start following the route
  void startRoute() {
    if (_mode != AppNavigationMode.routePreview || _routePath == null) return;
    
    _mode = AppNavigationMode.routeActive;
    debugPrint('[NavigationState] Started route following');
    notifyListeners();
  }
  
  /// View route overview (from route button during active route)
  void viewRouteOverview() {
    if (_mode != AppNavigationMode.routeActive || _routePath == null) return;
    
    _mode = AppNavigationMode.routeOverview;
    debugPrint('[NavigationState] Viewing route overview');
    notifyListeners();
  }
  
  /// Return to active route from overview
  void returnToActiveRoute() {
    if (_mode != AppNavigationMode.routeOverview) return;
    
    _mode = AppNavigationMode.routeActive;
    debugPrint('[NavigationState] Returned to active route');
    notifyListeners();
  }
  
  /// Cancel route and return to normal mode
  void cancelRoute() {
    if (!isInRouteMode) return;
    
    _mode = AppNavigationMode.normal;
    _routeStart = null;
    _routeEnd = null;
    _routeStartAddress = null;
    _routeEndAddress = null;
    _routePath = null;
    _routeDistance = null;
    _provisionalPinLocation = null;
    _provisionalPinAddress = null;
    debugPrint('[NavigationState] Cancelled route');
    notifyListeners();
  }
  
  /// Search functionality (delegates to existing search service)
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
      debugPrint('[NavigationState] Found ${results.length} results for "$query"');
    } catch (e) {
      debugPrint('[NavigationState] Search failed: $e');
      _searchResults = [];
    }
    
    _setSearchLoading(false);
  }
  
  /// Clear search results
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
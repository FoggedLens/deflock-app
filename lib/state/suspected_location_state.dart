import 'package:flutter/foundation.dart';

import '../models/suspected_location.dart';
import '../services/suspected_location_service.dart';

class SuspectedLocationState extends ChangeNotifier {
  final SuspectedLocationService _service = SuspectedLocationService();
  
  SuspectedLocation? _selectedLocation;
  bool _isLoading = false;

  /// Currently selected suspected location (for detail view)
  SuspectedLocation? get selectedLocation => _selectedLocation;

  /// Get suspected locations in bounds (this should be called by the map view)
  List<SuspectedLocation> getLocationsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) {
    return _service.getLocationsInBounds(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  /// Whether suspected locations are enabled
  bool get isEnabled => _service.isEnabled;

  /// Whether currently loading data
  bool get isLoading => _isLoading;

  /// Last time data was fetched
  DateTime? get lastFetchTime => _service.lastFetchTime;

  /// Initialize the state
  Future<void> init({bool offlineMode = false}) async {
    await _service.init(offlineMode: offlineMode);
    notifyListeners();
  }

  /// Enable or disable suspected locations
  Future<void> setEnabled(bool enabled) async {
    await _service.setEnabled(enabled);
    
    // If enabling and no data exists, fetch it now
    if (enabled && !_service.hasData) {
      await _fetchData();
    }
    
    notifyListeners();
  }

  /// Manually refresh the data (force refresh)
  Future<bool> refreshData() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final success = await _service.forceRefresh();
      return success;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Internal method to fetch data if needed with loading state management
  Future<bool> _fetchData() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final success = await _service.fetchDataIfNeeded();
      return success;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Select a suspected location for detail view
  void selectLocation(SuspectedLocation location) {
    _selectedLocation = location;
    notifyListeners();
  }

  /// Clear the selected location
  void clearSelection() {
    _selectedLocation = null;
    notifyListeners();
  }


}
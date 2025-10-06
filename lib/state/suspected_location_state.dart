import 'package:flutter/foundation.dart';

import '../models/suspected_location.dart';
import '../services/suspected_location_service.dart';

class SuspectedLocationState extends ChangeNotifier {
  final SuspectedLocationService _service = SuspectedLocationService();
  
  SuspectedLocation? _selectedLocation;
  bool _isLoading = false;

  /// Currently selected suspected location (for detail view)
  SuspectedLocation? get selectedLocation => _selectedLocation;

  /// All suspected locations
  List<SuspectedLocation> get locations => _service.locations;

  /// Whether suspected locations are enabled
  bool get isEnabled => _service.isEnabled;

  /// Whether currently loading data
  bool get isLoading => _isLoading || _service.isLoading;

  /// Last time data was fetched
  DateTime? get lastFetchTime => _service.lastFetchTime;

  /// Initialize the state
  Future<void> init() async {
    await _service.init();
    notifyListeners();
  }

  /// Enable or disable suspected locations
  Future<void> setEnabled(bool enabled) async {
    await _service.setEnabled(enabled);
    notifyListeners();
  }

  /// Manually refresh the data
  Future<bool> refreshData() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final success = await _service.refreshData();
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

  /// Get suspected locations within a bounding box
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
}
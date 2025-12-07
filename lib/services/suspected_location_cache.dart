import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/suspected_location.dart';
import 'suspected_location_service.dart';
import 'suspected_location_database.dart';

class SuspectedLocationCache extends ChangeNotifier {
  static final SuspectedLocationCache _instance = SuspectedLocationCache._();
  factory SuspectedLocationCache() => _instance;
  SuspectedLocationCache._();

  final SuspectedLocationDatabase _database = SuspectedLocationDatabase();
  
  // Simple cache: just hold the currently visible locations
  List<SuspectedLocation> _currentLocations = [];
  String? _currentBoundsKey;
  bool _isLoading = false;
  
  /// Get suspected locations within specific bounds (async version)
  Future<List<SuspectedLocation>> getLocationsForBounds(LatLngBounds bounds) async {
    if (!SuspectedLocationService().isEnabled) {
      return [];
    }
    
    final boundsKey = _getBoundsKey(bounds);
    
    // If this is the same bounds we're already showing, return current cache
    if (boundsKey == _currentBoundsKey) {
      return _currentLocations;
    }
    
    try {
      // Query database for locations in bounds
      final locations = await _database.getLocationsInBounds(bounds);
      
      // Update cache
      _currentLocations = locations;
      _currentBoundsKey = boundsKey;
      
      return locations;
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error querying database: $e');
      return [];
    }
  }
  
  /// Get suspected locations within specific bounds (synchronous version for UI)
  /// Returns current cache immediately, triggers async update if bounds changed
  List<SuspectedLocation> getLocationsForBoundsSync(LatLngBounds bounds) {
    if (!SuspectedLocationService().isEnabled) {
      return [];
    }
    
    final boundsKey = _getBoundsKey(bounds);
    
    // If bounds haven't changed, return current cache immediately
    if (boundsKey == _currentBoundsKey) {
      return _currentLocations;
    }
    
    // Bounds changed - trigger async update but keep showing current cache
    if (!_isLoading) {
      _isLoading = true;
      _updateCacheAsync(bounds, boundsKey);
    }
    
    // Return current cache (keeps suspected locations visible during map movement)
    return _currentLocations;
  }
  
  /// Simple async update - no complex caching, just swap when done
  void _updateCacheAsync(LatLngBounds bounds, String boundsKey) async {
    try {
      final locations = await _database.getLocationsInBounds(bounds);
      
      // Only update if this is still the most recent request
      if (boundsKey == _getBoundsKey(bounds) || _currentBoundsKey == null) {
        _currentLocations = locations;
        _currentBoundsKey = boundsKey;
        notifyListeners(); // Trigger UI update
      }
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error updating cache: $e');
    } finally {
      _isLoading = false;
    }
  }
  
  /// Generate cache key for bounds
  String _getBoundsKey(LatLngBounds bounds) {
    return '${bounds.north.toStringAsFixed(4)},${bounds.south.toStringAsFixed(4)},${bounds.east.toStringAsFixed(4)},${bounds.west.toStringAsFixed(4)}';
  }
  
  /// Initialize the cache (ensures database is ready)
  Future<void> loadFromStorage() async {
    try {
      await _database.init();
      debugPrint('[SuspectedLocationCache] Database initialized successfully');
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error initializing database: $e');
    }
  }
  
  /// Process raw CSV data and save to database
  Future<void> processAndSave(
    List<Map<String, dynamic>> rawData, 
    DateTime fetchTime,
  ) async {
    try {
      debugPrint('[SuspectedLocationCache] Processing ${rawData.length} raw entries...');
      
      // Clear cache since data will change
      _currentLocations = [];
      _currentBoundsKey = null;
      _isLoading = false;
      
      // Insert data into database in batch
      await _database.insertBatch(rawData, fetchTime);
      
      final totalCount = await _database.getTotalCount();
      debugPrint('[SuspectedLocationCache] Processed and saved $totalCount entries to database');
      
      notifyListeners();
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error processing and saving: $e');
      rethrow;
    }
  }
  
  /// Clear all cached data
  Future<void> clear() async {
    _currentLocations = [];
    _currentBoundsKey = null;
    _isLoading = false;
    await _database.clearAllData();
    notifyListeners();
  }
  
  /// Get last fetch time
  Future<DateTime?> get lastFetchTime => _database.getLastFetchTime();
  
  /// Get total count of processed entries
  Future<int> get totalCount => _database.getTotalCount();
  
  /// Check if we have data
  Future<bool> get hasData => _database.hasData();
}
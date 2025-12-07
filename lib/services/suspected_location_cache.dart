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
  final Map<String, List<SuspectedLocation>> _boundsCache = {};
  
  // Add a synchronous cache for UI responsiveness
  // This holds recently fetched bounds data to support synchronous API calls
  final Map<String, List<SuspectedLocation>> _syncCache = {};
  final Set<String> _pendingQueries = {};
  
  /// Get suspected locations within specific bounds (async version)
  Future<List<SuspectedLocation>> getLocationsForBounds(LatLngBounds bounds) async {
    if (!SuspectedLocationService().isEnabled) {
      return [];
    }
    
    final boundsKey = '${bounds.north.toStringAsFixed(4)},${bounds.south.toStringAsFixed(4)},${bounds.east.toStringAsFixed(4)},${bounds.west.toStringAsFixed(4)}';
    
    // Check cache first
    if (_boundsCache.containsKey(boundsKey)) {
      return _boundsCache[boundsKey]!;
    }
    
    try {
      // Query database for locations in bounds
      final locations = await _database.getLocationsInBounds(bounds);
      
      // Cache the result in both caches
      _boundsCache[boundsKey] = locations;
      _syncCache[boundsKey] = locations;
      
      // Limit cache sizes to prevent memory issues
      if (_boundsCache.length > 100) {
        final oldestKey = _boundsCache.keys.first;
        _boundsCache.remove(oldestKey);
      }
      if (_syncCache.length > 50) {
        final oldestKey = _syncCache.keys.first;
        _syncCache.remove(oldestKey);
      }
      
      return locations;
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error querying database: $e');
      return [];
    }
  }
  
  /// Get suspected locations within specific bounds (synchronous version for UI)
  /// This returns cached data immediately and triggers async fetch if needed
  List<SuspectedLocation> getLocationsForBoundsSync(LatLngBounds bounds) {
    if (!SuspectedLocationService().isEnabled) {
      return [];
    }
    
    final boundsKey = '${bounds.north.toStringAsFixed(4)},${bounds.south.toStringAsFixed(4)},${bounds.east.toStringAsFixed(4)},${bounds.west.toStringAsFixed(4)}';
    
    // Return sync cache immediately if available
    if (_syncCache.containsKey(boundsKey)) {
      return _syncCache[boundsKey]!;
    }
    
    // If not cached and not already being fetched, trigger async fetch
    if (!_pendingQueries.contains(boundsKey)) {
      _pendingQueries.add(boundsKey);
      _fetchAndCacheAsync(bounds, boundsKey);
    }
    
    // Return empty list immediately (will be updated when async fetch completes)
    return [];
  }
  
  /// Async fetch and cache helper
  void _fetchAndCacheAsync(LatLngBounds bounds, String boundsKey) async {
    try {
      final locations = await _database.getLocationsInBounds(bounds);
      
      _syncCache[boundsKey] = locations;
      _boundsCache[boundsKey] = locations;
      
      // Limit cache sizes
      if (_syncCache.length > 50) {
        final oldestKey = _syncCache.keys.first;
        _syncCache.remove(oldestKey);
      }
      if (_boundsCache.length > 100) {
        final oldestKey = _boundsCache.keys.first;
        _boundsCache.remove(oldestKey);
      }
      
      // Notify listeners to trigger UI rebuild
      notifyListeners();
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error in async fetch: $e');
    } finally {
      _pendingQueries.remove(boundsKey);
    }
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
      
      // Clear all caches since data will change
      _boundsCache.clear();
      _syncCache.clear();
      _pendingQueries.clear();
      
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
    _boundsCache.clear();
    _syncCache.clear();
    _pendingQueries.clear();
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
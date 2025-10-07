import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

import '../models/suspected_location.dart';
import 'suspected_location_service.dart';

/// Lightweight entry with pre-calculated centroid for efficient bounds checking
class SuspectedLocationEntry {
  final Map<String, dynamic> rawData;
  final LatLng centroid;
  
  SuspectedLocationEntry({required this.rawData, required this.centroid});
  
  Map<String, dynamic> toJson() => {
    'rawData': rawData,
    'centroid': [centroid.latitude, centroid.longitude],
  };
  
  factory SuspectedLocationEntry.fromJson(Map<String, dynamic> json) {
    final centroidList = json['centroid'] as List;
    return SuspectedLocationEntry(
      rawData: Map<String, dynamic>.from(json['rawData']),
      centroid: LatLng(
        (centroidList[0] as num).toDouble(),
        (centroidList[1] as num).toDouble(),
      ),
    );
  }
}

class SuspectedLocationCache extends ChangeNotifier {
  static final SuspectedLocationCache _instance = SuspectedLocationCache._();
  factory SuspectedLocationCache() => _instance;
  SuspectedLocationCache._();

  static const String _prefsKeyProcessedData = 'suspected_locations_processed_data';
  static const String _prefsKeyLastFetch = 'suspected_locations_last_fetch';
  
  List<SuspectedLocationEntry> _processedEntries = [];
  DateTime? _lastFetchTime;
  final Map<String, List<SuspectedLocation>> _boundsCache = {};
  
  /// Get suspected locations within specific bounds (cached)
  List<SuspectedLocation> getLocationsForBounds(LatLngBounds bounds) {
    if (!SuspectedLocationService().isEnabled) {
      debugPrint('[SuspectedLocationCache] Service not enabled');
      return [];
    }
    
    final boundsKey = '${bounds.north.toStringAsFixed(4)},${bounds.south.toStringAsFixed(4)},${bounds.east.toStringAsFixed(4)},${bounds.west.toStringAsFixed(4)}';
    
    // debugPrint('[SuspectedLocationCache] Getting locations for bounds: $boundsKey, processed entries count: ${_processedEntries.length}');
    
    // Check cache first
    if (_boundsCache.containsKey(boundsKey)) {
      debugPrint('[SuspectedLocationCache] Using cached result: ${_boundsCache[boundsKey]!.length} locations');
      return _boundsCache[boundsKey]!;
    }
    
    // Filter processed entries for this bounds (very fast since centroids are pre-calculated)
    final locations = <SuspectedLocation>[];
    int inBoundsCount = 0;
    
    for (final entry in _processedEntries) {
      // Quick bounds check using pre-calculated centroid
      final lat = entry.centroid.latitude;
      final lng = entry.centroid.longitude;
      
      if (lat <= bounds.north && lat >= bounds.south && 
          lng <= bounds.east && lng >= bounds.west) {
        try {
          // Only create SuspectedLocation object if it's in bounds
          final location = SuspectedLocation.fromCsvRow(entry.rawData);
          locations.add(location);
          inBoundsCount++;
        } catch (e) {
          // Skip invalid entries
          continue;
        }
      }
    }
    
    // debugPrint('[SuspectedLocationCache] Checked ${_processedEntries.length} entries, $inBoundsCount in bounds, result: ${locations.length} locations');
    
    // Cache the result
    _boundsCache[boundsKey] = locations;
    
    // Limit cache size to prevent memory issues
    if (_boundsCache.length > 100) {
      final oldestKey = _boundsCache.keys.first;
      _boundsCache.remove(oldestKey);
    }
    
    return locations;
  }
  
  /// Load processed data from storage
  Future<void> loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load last fetch time
      final lastFetchMs = prefs.getInt(_prefsKeyLastFetch);
      if (lastFetchMs != null) {
        _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchMs);
      }
      
      // Load processed data
      final processedDataString = prefs.getString(_prefsKeyProcessedData);
      if (processedDataString != null) {
        final List<dynamic> processedDataList = jsonDecode(processedDataString);
        _processedEntries = processedDataList
            .map((json) => SuspectedLocationEntry.fromJson(json as Map<String, dynamic>))
            .toList();
        debugPrint('[SuspectedLocationCache] Loaded ${_processedEntries.length} processed entries from storage');
      }
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error loading from storage: $e');
      _processedEntries.clear();
      _lastFetchTime = null;
    }
  }
  
  /// Process raw CSV data and save to storage (calculates centroids once)
  Future<void> processAndSave(
    List<Map<String, dynamic>> rawData, 
    DateTime fetchTime, {
    void Function(String message, double? progress)? onProgress,
  }) async {
    try {
      debugPrint('[SuspectedLocationCache] Processing ${rawData.length} raw entries...');
      
      final processedEntries = <SuspectedLocationEntry>[];
      int validCount = 0;
      int errorCount = 0;
      int zeroCoordCount = 0;
      
      for (int i = 0; i < rawData.length; i++) {
        final rowData = rawData[i];
        
        // Report progress every 1000 entries
        if (i % 1000 == 0) {
          final progress = i / rawData.length;
          onProgress?.call('Calculating coordinates: ${i + 1}/${rawData.length}', progress);
        }
        
        try {
          // Create a temporary SuspectedLocation to extract the centroid
          final tempLocation = SuspectedLocation.fromCsvRow(rowData);
          
          // Only save if we have a valid centroid (not at 0,0)
          if (tempLocation.centroid.latitude != 0 || tempLocation.centroid.longitude != 0) {
            processedEntries.add(SuspectedLocationEntry(
              rawData: rowData,
              centroid: tempLocation.centroid,
            ));
            validCount++;
          } else {
            zeroCoordCount++;
            if (i < 3) { // Log first few zero coord cases
              debugPrint('[SuspectedLocationCache] Row $i has zero coordinates: ticket=${rowData['ticket_no']}, location=${rowData['location']?.toString().length} chars');
            }
          }
        } catch (e) {
          errorCount++;
          if (errorCount <= 5) { // Log first few errors
            debugPrint('[SuspectedLocationCache] Row $i error: $e, ticket=${rowData['ticket_no']}');
          }
          continue;
        }
      }
      
      debugPrint('[SuspectedLocationCache] Processing complete - Valid: $validCount, Zero coords: $zeroCoordCount, Errors: $errorCount');
      
      _processedEntries = processedEntries;
      _lastFetchTime = fetchTime;
      
      // Clear bounds cache since data changed
      _boundsCache.clear();
      
      final prefs = await SharedPreferences.getInstance();
      
      // Save processed data
      final processedDataString = jsonEncode(processedEntries.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKeyProcessedData, processedDataString);
      
      // Save last fetch time
      await prefs.setInt(_prefsKeyLastFetch, fetchTime.millisecondsSinceEpoch);
      
      // Log coordinate ranges for debugging
      if (processedEntries.isNotEmpty) {
        double minLat = processedEntries.first.centroid.latitude;
        double maxLat = minLat;
        double minLng = processedEntries.first.centroid.longitude;
        double maxLng = minLng;
        
        for (final entry in processedEntries) {
          final lat = entry.centroid.latitude;
          final lng = entry.centroid.longitude;
          if (lat < minLat) minLat = lat;
          if (lat > maxLat) maxLat = lat;
          if (lng < minLng) minLng = lng;
          if (lng > maxLng) maxLng = lng;
        }
        
        debugPrint('[SuspectedLocationCache] Coordinate ranges - Lat: $minLat to $maxLat, Lng: $minLng to $maxLng');
      }
      
      debugPrint('[SuspectedLocationCache] Processed and saved $validCount valid entries (${processedEntries.length} total)');
      notifyListeners();
    } catch (e) {
      debugPrint('[SuspectedLocationCache] Error processing and saving: $e');
    }
  }
  
  /// Clear all cached data
  void clear() {
    _processedEntries.clear();
    _boundsCache.clear();
    _lastFetchTime = null;
    notifyListeners();
  }
  
  /// Get last fetch time
  DateTime? get lastFetchTime => _lastFetchTime;
  
  /// Get total count of processed entries
  int get totalCount => _processedEntries.length;
  
  /// Check if we have data
  bool get hasData => _processedEntries.isNotEmpty;
}
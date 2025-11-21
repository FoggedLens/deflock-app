import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';

import '../dev_config.dart';
import '../models/suspected_location.dart';
import 'suspected_location_cache.dart';

class SuspectedLocationService {
  static final SuspectedLocationService _instance = SuspectedLocationService._();
  factory SuspectedLocationService() => _instance;
  SuspectedLocationService._();

  static const String _prefsKeyEnabled = 'suspected_locations_enabled';
  static const Duration _maxAge = Duration(days: 7);
  static const Duration _timeout = Duration(seconds: 30);
  
  final SuspectedLocationCache _cache = SuspectedLocationCache();
  bool _isEnabled = false;

  /// Get last fetch time
  DateTime? get lastFetchTime => _cache.lastFetchTime;

  /// Check if suspected locations are enabled
  bool get isEnabled => _isEnabled;

  /// Initialize the service - load from storage and check if refresh needed
  Future<void> init({bool offlineMode = false}) async {
    await _loadFromStorage();
    
    // Load cache data
    await _cache.loadFromStorage();
    
    // Only auto-fetch if enabled, data is stale or missing, and we are not offline
    if (_isEnabled && _shouldRefresh() && !offlineMode) {
      debugPrint('[SuspectedLocationService] Auto-refreshing CSV data on startup (older than $_maxAge or missing)');
      await _fetchData();
    } else if (_isEnabled && _shouldRefresh() && offlineMode) {
      debugPrint('[SuspectedLocationService] Skipping auto-refresh due to offline mode - data is ${_cache.lastFetchTime != null ? 'outdated' : 'missing'}');
    }
  }

  /// Enable or disable suspected locations
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
    
    // If disabling, clear the cache
    if (!enabled) {
      _cache.clear();
    }
    // Note: If enabling and no data, the state layer will call fetchDataIfNeeded()
  }

  /// Check if cache has any data
  bool get hasData => _cache.hasData;

  /// Get last fetch time  
  DateTime? get lastFetch => _cache.lastFetchTime;

  /// Fetch data if needed (for enabling suspected locations when no data exists)
  Future<bool> fetchDataIfNeeded() async {
    if (!_shouldRefresh()) {
      debugPrint('[SuspectedLocationService] Data is fresh, skipping fetch');
      return true; // Already have fresh data
    }
    return await _fetchData();
  }

  /// Force refresh the data (for manual refresh button)
  Future<bool> forceRefresh() async {
    return await _fetchData();
  }

  /// Check if data should be refreshed
  bool _shouldRefresh() {
    if (!_cache.hasData) return true;
    if (_cache.lastFetchTime == null) return true;
    return DateTime.now().difference(_cache.lastFetchTime!) > _maxAge;
  }

  /// Load settings from shared preferences
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load enabled state
      _isEnabled = prefs.getBool(_prefsKeyEnabled) ?? false;
      
      debugPrint('[SuspectedLocationService] Loaded settings - enabled: $_isEnabled');
    } catch (e) {
      debugPrint('[SuspectedLocationService] Error loading from storage: $e');
    }
  }

  /// Fetch data from the CSV URL
  Future<bool> _fetchData() async {
    try {
      debugPrint('[SuspectedLocationService] Fetching CSV data from $dev.kSuspectedLocationsCsvUrl');
      
      final response = await http.get(
        Uri.parse(dev.kSuspectedLocationsCsvUrl),
        headers: {
          'User-Agent': 'DeFlock/1.0 (OSM surveillance mapping app)',
        },
      ).timeout(_timeout);
      
      if (response.statusCode != 200) {
        debugPrint('[SuspectedLocationService] HTTP error ${response.statusCode}');
        return false;
      }
      
      // Parse CSV with proper field separator and quote handling
      final csvData = await compute(_parseCSV, response.body);
      debugPrint('[SuspectedLocationService] Parsed ${csvData.length} rows from CSV');
      
      if (csvData.isEmpty) {
        debugPrint('[SuspectedLocationService] Empty CSV data');
        return false;
      }
      
      // First row should be headers
      final headers = csvData.first.map((h) => h.toString().toLowerCase()).toList();
      debugPrint('[SuspectedLocationService] Headers: $headers');
      final dataRows = csvData.skip(1);
      debugPrint('[SuspectedLocationService] Data rows count: ${dataRows.length}');
      
      // Find required column indices - we only need ticket_no and location
      final ticketNoIndex = headers.indexOf('ticket_no');
      final locationIndex = headers.indexOf('location');
      
      debugPrint('[SuspectedLocationService] Column indices - ticket_no: $ticketNoIndex, location: $locationIndex');
      
      if (ticketNoIndex == -1 || locationIndex == -1) {
        debugPrint('[SuspectedLocationService] Required columns not found in CSV. Headers: $headers');
        return false;
      }
      
      // Parse rows and store all data dynamically
      final List<Map<String, dynamic>> rawDataList = [];
      int rowIndex = 0;
      int validRows = 0;
      for (final row in dataRows) {
        rowIndex++;
        try {
          final Map<String, dynamic> rowData = {};
          
          // Store all columns dynamically
          for (int i = 0; i < headers.length && i < row.length; i++) {
            final headerName = headers[i];
            final cellValue = row[i];
            if (cellValue != null) {
              rowData[headerName] = cellValue;
            }
          }
          
          // Basic validation - must have ticket_no and location
          if (rowData['ticket_no']?.toString().isNotEmpty == true && 
              rowData['location']?.toString().isNotEmpty == true) {
            rawDataList.add(rowData);
            validRows++;
          }
          
        } catch (e, stackTrace) {
          // Skip rows that can't be parsed
          debugPrint('[SuspectedLocationService] Error parsing row $rowIndex: $e');
          continue;
        }
      }
      
      debugPrint('[SuspectedLocationService] Parsed $validRows valid rows from ${dataRows.length} total rows');
      
      final fetchTime = DateTime.now();
      
      // Process raw data and save (calculates centroids once)
      await _cache.processAndSave(rawDataList, fetchTime);
      
      debugPrint('[SuspectedLocationService] Successfully fetched and stored $validRows valid raw entries (${rawDataList.length} total)');
      return true;
      
    } catch (e, stackTrace) {
      debugPrint('[SuspectedLocationService] Error fetching data: $e');
      debugPrint('[SuspectedLocationService] Stack trace: $stackTrace');
      return false;
    }
  }

  /// Get suspected locations within a bounding box
  List<SuspectedLocation> getLocationsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) {
    return _cache.getLocationsForBounds(LatLngBounds(
      LatLng(north, west),
      LatLng(south, east),
    ));
  }
}

/// Simple CSV parser for compute() - must be top-level function
List<List<dynamic>> _parseCSV(String csvBody) {
  return const CsvToListConverter(
    fieldDelimiter: ',',
    textDelimiter: '"',
    eol: '\n',
  ).convert(csvBody);
}
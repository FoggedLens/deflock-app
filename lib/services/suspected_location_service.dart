import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';

import '../models/suspected_location.dart';

class SuspectedLocationService {
  static final SuspectedLocationService _instance = SuspectedLocationService._();
  factory SuspectedLocationService() => _instance;
  SuspectedLocationService._();

  static const String _csvUrl = 'https://alprwatch.org/pub/flock_utilities_mini_2025-10-06.csv';
  static const String _prefsKeyData = 'suspected_locations_data';
  static const String _prefsKeyLastFetch = 'suspected_locations_last_fetch';
  static const String _prefsKeyEnabled = 'suspected_locations_enabled';
  static const Duration _maxAge = Duration(days: 7);
  static const Duration _timeout = Duration(seconds: 30);
  
  List<SuspectedLocation> _locations = [];
  DateTime? _lastFetchTime;
  bool _isEnabled = false;
  bool _isLoading = false;

  /// Get all suspected locations
  List<SuspectedLocation> get locations => List.unmodifiable(_locations);

  /// Get last fetch time
  DateTime? get lastFetchTime => _lastFetchTime;

  /// Check if suspected locations are enabled
  bool get isEnabled => _isEnabled;

  /// Check if currently loading
  bool get isLoading => _isLoading;

  /// Initialize the service - load from storage and check if refresh needed
  Future<void> init() async {
    await _loadFromStorage();
    
    // Only auto-fetch if enabled and data is stale or missing
    if (_isEnabled && _shouldRefresh()) {
      await _fetchData();
    }
  }

  /// Enable or disable suspected locations
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
    
    // If enabling for the first time and no data, fetch it
    if (enabled && _locations.isEmpty) {
      await _fetchData();
    }
    
    // If disabling, clear the data from memory (but keep in storage)
    if (!enabled) {
      _locations.clear();
    }
  }

  /// Manually refresh the data
  Future<bool> refreshData() async {
    return await _fetchData();
  }

  /// Check if data should be refreshed
  bool _shouldRefresh() {
    if (_locations.isEmpty) return true;
    if (_lastFetchTime == null) return true;
    return DateTime.now().difference(_lastFetchTime!) > _maxAge;
  }

  /// Load data from shared preferences
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load enabled state
      _isEnabled = prefs.getBool(_prefsKeyEnabled) ?? false;
      
      // Load last fetch time
      final lastFetchMs = prefs.getInt(_prefsKeyLastFetch);
      if (lastFetchMs != null) {
        _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchMs);
      }
      
      // Only load data if enabled
      if (!_isEnabled) {
        return;
      }
      
      // Load data
      final jsonString = prefs.getString(_prefsKeyData);
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _locations = jsonList
            .map((json) => SuspectedLocation.fromJson(json as Map<String, dynamic>))
            .toList();
        debugPrint('[SuspectedLocationService] Loaded ${_locations.length} suspected locations from storage');
      }
    } catch (e) {
      debugPrint('[SuspectedLocationService] Error loading from storage: $e');
      _locations.clear();
      _lastFetchTime = null;
    }
  }

  /// Save data to shared preferences
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save data
      final jsonString = jsonEncode(_locations.map((loc) => loc.toJson()).toList());
      await prefs.setString(_prefsKeyData, jsonString);
      
      // Save last fetch time
      if (_lastFetchTime != null) {
        await prefs.setInt(_prefsKeyLastFetch, _lastFetchTime!.millisecondsSinceEpoch);
      }
      
      debugPrint('[SuspectedLocationService] Saved ${_locations.length} suspected locations to storage');
    } catch (e) {
      debugPrint('[SuspectedLocationService] Error saving to storage: $e');
    }
  }

  /// Fetch data from the CSV URL
  Future<bool> _fetchData() async {
    if (_isLoading) return false;
    
    _isLoading = true;
    try {
      debugPrint('[SuspectedLocationService] Fetching CSV data from $_csvUrl');
      
      final response = await http.get(
        Uri.parse(_csvUrl),
        headers: {
          'User-Agent': 'DeFlock/1.0 (OSM surveillance mapping app)',
        },
      ).timeout(_timeout);
      
      if (response.statusCode != 200) {
        debugPrint('[SuspectedLocationService] HTTP error ${response.statusCode}');
        return false;
      }
      
      // Parse CSV with proper field separator and quote handling
      final csvData = const CsvToListConverter(
        fieldDelimiter: ',',
        textDelimiter: '"',
        eol: '\n',
      ).convert(response.body);
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
      
      // Find required column indices
      final ticketNoIndex = headers.indexOf('ticket_no');
      final urlFullIndex = headers.indexOf('url_full');
      final addrIndex = headers.indexOf('addr');
      final streetIndex = headers.indexOf('street');
      final cityIndex = headers.indexOf('city');
      final stateIndex = headers.indexOf('state');
      final digSiteIntersectingStreetIndex = headers.indexOf('dig_site_intersecting_street');
      final digWorkDoneForIndex = headers.indexOf('dig_work_done_for');
      final digSiteRemarksIndex = headers.indexOf('dig_site_remarks');
      final locationIndex = headers.indexOf('location');
      
      debugPrint('[SuspectedLocationService] Column indices - ticket_no: $ticketNoIndex, location: $locationIndex');
      
      if (ticketNoIndex == -1 || locationIndex == -1) {
        debugPrint('[SuspectedLocationService] Required columns not found in CSV. Headers: $headers');
        return false;
      }
      
      // Parse rows
      final List<SuspectedLocation> newLocations = [];
      int rowIndex = 0;
      for (final row in dataRows) {
        rowIndex++;
        try {
          final Map<String, dynamic> rowData = {};
          
          if (ticketNoIndex < row.length) rowData['ticket_no'] = row[ticketNoIndex];
          if (urlFullIndex != -1 && urlFullIndex < row.length) rowData['url_full'] = row[urlFullIndex];
          if (addrIndex != -1 && addrIndex < row.length) rowData['addr'] = row[addrIndex];
          if (streetIndex != -1 && streetIndex < row.length) rowData['street'] = row[streetIndex];
          if (cityIndex != -1 && cityIndex < row.length) rowData['city'] = row[cityIndex];
          if (stateIndex != -1 && stateIndex < row.length) rowData['state'] = row[stateIndex];
          if (digSiteIntersectingStreetIndex != -1 && digSiteIntersectingStreetIndex < row.length) {
            rowData['dig_site_intersecting_street'] = row[digSiteIntersectingStreetIndex];
          }
          if (digWorkDoneForIndex != -1 && digWorkDoneForIndex < row.length) {
            rowData['dig_work_done_for'] = row[digWorkDoneForIndex];
          }
          if (digSiteRemarksIndex != -1 && digSiteRemarksIndex < row.length) {
            rowData['dig_site_remarks'] = row[digSiteRemarksIndex];
          }
          if (locationIndex < row.length) rowData['location'] = row[locationIndex];
          
          debugPrint('[SuspectedLocationService] Row $rowIndex data keys: ${rowData.keys.toList()}');
          if (rowIndex <= 3) { // Log first few rows
            debugPrint('[SuspectedLocationService] Row $rowIndex ticket_no: ${rowData['ticket_no']}, location length: ${rowData['location']?.toString().length}');
          }
          
          final location = SuspectedLocation.fromCsvRow(rowData);
          newLocations.add(location);
        } catch (e, stackTrace) {
          // Skip rows that can't be parsed
          debugPrint('[SuspectedLocationService] Error parsing row $rowIndex: $e');
          debugPrint('[SuspectedLocationService] Stack trace: $stackTrace');
          continue;
        }
      }
      
      _locations = newLocations;
      _lastFetchTime = DateTime.now();
      
      // Save to storage
      await _saveToStorage();
      
      debugPrint('[SuspectedLocationService] Successfully fetched and parsed ${_locations.length} suspected locations');
      return true;
      
    } catch (e, stackTrace) {
      debugPrint('[SuspectedLocationService] Error fetching data: $e');
      debugPrint('[SuspectedLocationService] Stack trace: $stackTrace');
      return false;
    } finally {
      _isLoading = false;
    }
  }

  /// Get suspected locations within a bounding box
  List<SuspectedLocation> getLocationsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) {
    if (!_isEnabled || _locations.isEmpty) return [];
    
    return _locations.where((location) {
      final lat = location.centroid.latitude;
      final lng = location.centroid.longitude;
      
      return lat <= north && lat >= south && lng <= east && lng >= west;
    }).toList();
  }
}
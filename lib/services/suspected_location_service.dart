import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csv/csv.dart';

import '../dev_config.dart';
import '../models/suspected_location.dart';
import 'http_client.dart';
import 'suspected_location_cache.dart';

class SuspectedLocationService {
  static final SuspectedLocationService _instance = SuspectedLocationService._();
  factory SuspectedLocationService() => _instance;
  SuspectedLocationService._();

  static const String _prefsKeyEnabled = 'suspected_locations_enabled';
  static const Duration _maxAge = Duration(days: 7);
  static const Duration _timeout = Duration(minutes: 5); // Increased for large CSV files (100MB+)
  
  final SuspectedLocationCache _cache = SuspectedLocationCache();
  bool _isEnabled = false;

  /// Get last fetch time
  Future<DateTime?> get lastFetchTime => _cache.lastFetchTime;

  /// Check if suspected locations are enabled
  bool get isEnabled => _isEnabled;

  /// Initialize the service - load from storage and check if refresh needed
  Future<void> init({bool offlineMode = false}) async {
    await _loadFromStorage();

    // Load cache data
    await _cache.loadFromStorage();

    // Only auto-fetch if enabled, data is stale or missing, and we are not offline
    if (_isEnabled && (await _shouldRefresh()) && !offlineMode) {
      debugPrint('[SuspectedLocationService] Auto-refreshing CSV data on startup (older than $_maxAge or missing)');
      await _fetchData();
    } else if (_isEnabled && (await _shouldRefresh()) && offlineMode) {
      final lastFetch = await _cache.lastFetchTime;
      debugPrint('[SuspectedLocationService] Skipping auto-refresh due to offline mode - data is ${lastFetch != null ? 'outdated' : 'missing'}');
    }
  }

  /// Fast, local-only init (SharedPrefs + SQLite). No network.
  Future<void> initLocal() async {
    await _loadFromStorage();
    await _cache.loadFromStorage();
  }

  /// Background refresh if data is stale. Fire-and-forget safe.
  Future<bool> refreshIfNeeded({bool offlineMode = false}) async {
    if (!_isEnabled || !(await _shouldRefresh())) return false;
    if (offlineMode) {
      final lastFetch = await _cache.lastFetchTime;
      debugPrint('[SuspectedLocationService] Skipping background refresh due to offline mode - data is ${lastFetch != null ? 'outdated' : 'missing'}');
      return false;
    }
    debugPrint('[SuspectedLocationService] Background-refreshing CSV data (older than $_maxAge or missing)');
    return await _fetchData();
  }

  /// Enable or disable suspected locations
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
    
    // If disabling, clear the cache
    if (!enabled) {
      await _cache.clear();
    }
    // Note: If enabling and no data, the state layer will call fetchDataIfNeeded()
  }

  /// Check if cache has any data
  Future<bool> get hasData => _cache.hasData;

  /// Get last fetch time  
  Future<DateTime?> get lastFetch => _cache.lastFetchTime;

  /// Fetch data if needed (for enabling suspected locations when no data exists)
  Future<bool> fetchDataIfNeeded({void Function(double)? onProgress}) async {
    if (!(await _shouldRefresh())) {
      debugPrint('[SuspectedLocationService] Data is fresh, skipping fetch');
      return true; // Already have fresh data
    }
    return await _fetchData(onProgress: onProgress);
  }

  /// Force refresh the data (for manual refresh button)
  Future<bool> forceRefresh({void Function(double)? onProgress}) async {
    return await _fetchData(onProgress: onProgress);
  }

  /// Check if data should be refreshed
  Future<bool> _shouldRefresh() async {
    if (!(await _cache.hasData)) return true;
    final lastFetch = await _cache.lastFetchTime;
    if (lastFetch == null) return true;
    return DateTime.now().difference(lastFetch) > _maxAge;
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
  Future<bool> _fetchData({void Function(double)? onProgress}) async {
    const maxRetries = 3;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('[SuspectedLocationService] Fetching CSV data from $kSuspectedLocationsCsvUrl (attempt $attempt/$maxRetries)');
        if (attempt == 1) {
          debugPrint('[SuspectedLocationService] This may take up to ${_timeout.inMinutes} minutes for large datasets...');
        }
        
        // Use streaming download for progress tracking
        final request = http.Request('GET', Uri.parse(kSuspectedLocationsCsvUrl));

        final client = UserAgentClient();
        final streamedResponse = await client.send(request).timeout(_timeout);
        
        if (streamedResponse.statusCode != 200) {
          debugPrint('[SuspectedLocationService] HTTP error ${streamedResponse.statusCode}');
          client.close();
          throw Exception('HTTP ${streamedResponse.statusCode}');
        }
        
        final contentLength = streamedResponse.contentLength;
        debugPrint('[SuspectedLocationService] Starting download of ${contentLength != null ? '$contentLength bytes' : 'unknown size'}...');
        
        // Download with progress tracking
        final chunks = <List<int>>[];
        int downloadedBytes = 0;
        
        await for (final chunk in streamedResponse.stream) {
          chunks.add(chunk);
          downloadedBytes += chunk.length;
          
          // Report progress if we know the total size
          if (contentLength != null && onProgress != null) {
            try {
              final progress = downloadedBytes / contentLength;
              onProgress(progress.clamp(0.0, 1.0));
            } catch (e) {
              // Don't let progress callback errors break the download
              debugPrint('[SuspectedLocationService] Progress callback error: $e');
            }
          }
        }
        
        client.close();
        
        // Combine chunks into single response body
        final bodyBytes = chunks.expand((chunk) => chunk).toList();
        final responseBody = String.fromCharCodes(bodyBytes);
        
        debugPrint('[SuspectedLocationService] Downloaded $downloadedBytes bytes, parsing CSV...');
        
        // Parse CSV with proper field separator and quote handling
        final csvData = await compute(_parseCSV, responseBody);
        debugPrint('[SuspectedLocationService] Parsed ${csvData.length} rows from CSV');
        
        if (csvData.isEmpty) {
          debugPrint('[SuspectedLocationService] Empty CSV data');
          throw Exception('Empty CSV data');
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
          throw Exception('Required columns not found in CSV');
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
            
          } catch (e) {
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
        debugPrint('[SuspectedLocationService] Attempt $attempt failed: $e');
        
        if (attempt == maxRetries) {
          debugPrint('[SuspectedLocationService] All $maxRetries attempts failed');
          debugPrint('[SuspectedLocationService] Stack trace: $stackTrace');
          return false;
        } else {
          // Wait before retrying (exponential backoff)
          final delay = Duration(seconds: attempt * 10);
          debugPrint('[SuspectedLocationService] Retrying in ${delay.inSeconds} seconds...');
          await Future.delayed(delay);
        }
      }
    }
    
    return false; // Should never reach here
  }

  /// Get suspected locations within a bounding box (async)
  Future<List<SuspectedLocation>> getLocationsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    return await _cache.getLocationsForBounds(LatLngBounds(
      LatLng(north, west),
      LatLng(south, east),
    ));
  }
  
  /// Get suspected locations within a bounding box (sync, for UI)
  List<SuspectedLocation> getLocationsInBoundsSync({
    required double north,
    required double south,
    required double east,
    required double west,
  }) {
    return _cache.getLocationsForBoundsSync(LatLngBounds(
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
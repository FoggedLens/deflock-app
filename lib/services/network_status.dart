import 'package:flutter/material.dart';
import 'dart:async';

import '../app_state.dart';

enum NetworkIssueType { osmTiles, overpassApi, both }
enum NetworkStatusType { waiting, issues, timedOut, noData, ready }

class NetworkStatus extends ChangeNotifier {
  static final NetworkStatus instance = NetworkStatus._();
  NetworkStatus._();

  bool _osmTilesHaveIssues = false;
  bool _overpassHasIssues = false;
  bool _isWaitingForData = false;
  bool _isTimedOut = false;
  bool _hasNoData = false;
  int _recentOfflineMisses = 0;
  Timer? _osmRecoveryTimer;
  Timer? _overpassRecoveryTimer;
  Timer? _waitingTimer;
  Timer? _noDataResetTimer;

  // Getters
  bool get hasAnyIssues => _osmTilesHaveIssues || _overpassHasIssues;
  bool get osmTilesHaveIssues => _osmTilesHaveIssues;
  bool get overpassHasIssues => _overpassHasIssues;
  bool get isWaitingForData => _isWaitingForData;
  bool get isTimedOut => _isTimedOut;
  bool get hasNoData => _hasNoData;
  
  NetworkStatusType get currentStatus {
    if (hasAnyIssues) return NetworkStatusType.issues;
    if (_isWaitingForData) return NetworkStatusType.waiting;
    if (_isTimedOut) return NetworkStatusType.timedOut;
    if (_hasNoData) return NetworkStatusType.noData;
    return NetworkStatusType.ready;
  }

  NetworkIssueType? get currentIssueType {
    if (_osmTilesHaveIssues && _overpassHasIssues) return NetworkIssueType.both;
    if (_osmTilesHaveIssues) return NetworkIssueType.osmTiles;
    if (_overpassHasIssues) return NetworkIssueType.overpassApi;
    return null;
  }

  /// Report OSM tile server issues
  void reportOsmTileIssue() {
    if (!_osmTilesHaveIssues) {
      _osmTilesHaveIssues = true;
      notifyListeners();
      debugPrint('[NetworkStatus] OSM tile server issues detected');
    }
    
    // Reset recovery timer - if we keep getting errors, keep showing indicator
    _osmRecoveryTimer?.cancel();
    _osmRecoveryTimer = Timer(const Duration(minutes: 2), () {
      _osmTilesHaveIssues = false;
      notifyListeners();
      debugPrint('[NetworkStatus] OSM tile server issues cleared');
    });
  }

  /// Report Overpass API issues
  void reportOverpassIssue() {
    if (!_overpassHasIssues) {
      _overpassHasIssues = true;
      notifyListeners();
      debugPrint('[NetworkStatus] Overpass API issues detected');
    }
    
    // Reset recovery timer
    _overpassRecoveryTimer?.cancel();
    _overpassRecoveryTimer = Timer(const Duration(minutes: 2), () {
      _overpassHasIssues = false;
      notifyListeners();
      debugPrint('[NetworkStatus] Overpass API issues cleared');
    });
  }

  /// Report successful operations to potentially clear issues faster
  void reportOsmTileSuccess() {
    // Clear issues immediately on success (they were likely temporary)
    if (_osmTilesHaveIssues) {
      debugPrint('[NetworkStatus] OSM tile server issues cleared after success');
      _osmTilesHaveIssues = false;
      _osmRecoveryTimer?.cancel();
      notifyListeners();
    }
  }

  void reportOverpassSuccess() {
    if (_overpassHasIssues) {
      debugPrint('[NetworkStatus] Overpass API issues cleared after success');
      _overpassHasIssues = false;
      _overpassRecoveryTimer?.cancel();
      notifyListeners();
    }
  }

  /// Set waiting status (show when loading tiles/cameras)
  void setWaiting() {
    // Clear any previous timeout/no-data state when starting new wait
    _isTimedOut = false;
    _hasNoData = false;
    _recentOfflineMisses = 0;
    _noDataResetTimer?.cancel();
    
    if (!_isWaitingForData) {
      _isWaitingForData = true;
      notifyListeners();
      debugPrint('[NetworkStatus] Waiting for data...');
    }
    
    // Set timeout to show appropriate status after reasonable time
    _waitingTimer?.cancel();
    _waitingTimer = Timer(const Duration(seconds: 10), () {
      _isWaitingForData = false;
      
      // If in offline mode, this is "no data" not "timed out"
      if (AppState.instance.offlineMode) {
        _hasNoData = true;
        debugPrint('[NetworkStatus] No offline data available (timeout in offline mode)');
      } else {
        _isTimedOut = true;
        debugPrint('[NetworkStatus] Data request timed out (online mode)');
      }
      
      notifyListeners();
    });
  }
  
  /// Clear waiting/timeout/no-data status when data arrives
  void clearWaiting() {
    if (_isWaitingForData || _isTimedOut || _hasNoData) {
      _isWaitingForData = false;
      _isTimedOut = false;
      _hasNoData = false;
      _recentOfflineMisses = 0;
      _waitingTimer?.cancel();
      _noDataResetTimer?.cancel();
      notifyListeners();
      debugPrint('[NetworkStatus] Waiting/timeout/no-data status cleared - data arrived');
    }
  }
  
  /// Report that a tile was not available offline
  void reportOfflineMiss() {
    _recentOfflineMisses++;
    debugPrint('[NetworkStatus] Offline miss #$_recentOfflineMisses');
    
    // If we get several misses in a short time, show "no data" status
    if (_recentOfflineMisses >= 3 && !_hasNoData) {
      _isWaitingForData = false;
      _isTimedOut = false;
      _hasNoData = true;
      _waitingTimer?.cancel();
      notifyListeners();
      debugPrint('[NetworkStatus] No offline data available for this area');
    }
    
    // Reset the miss counter after some time
    _noDataResetTimer?.cancel();
    _noDataResetTimer = Timer(const Duration(seconds: 5), () {
      _recentOfflineMisses = 0;
    });
  }

  @override
  void dispose() {
    _osmRecoveryTimer?.cancel();
    _overpassRecoveryTimer?.cancel();
    _waitingTimer?.cancel();
    _noDataResetTimer?.cancel();
    super.dispose();
  }
}
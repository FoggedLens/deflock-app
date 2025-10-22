import 'package:flutter/material.dart';
import 'dart:async';

import '../app_state.dart';

enum NetworkIssueType { osmTiles, overpassApi, both }
enum NetworkStatusType { waiting, issues, timedOut, noData, ready, success, nodeLimitReached }



class NetworkStatus extends ChangeNotifier {
  static final NetworkStatus instance = NetworkStatus._();
  NetworkStatus._();

  bool _osmTilesHaveIssues = false;
  bool _overpassHasIssues = false;
  bool _isWaitingForData = false;
  bool _isTimedOut = false;
  bool _hasNoData = false;
  bool _hasSuccess = false;
  int _recentOfflineMisses = 0;
  Timer? _osmRecoveryTimer;
  Timer? _overpassRecoveryTimer;
  Timer? _waitingTimer;
  Timer? _noDataResetTimer;
  Timer? _successResetTimer;
  bool _nodeLimitReached = false;
  Timer? _nodeLimitResetTimer;

  // Getters
  bool get hasAnyIssues => _osmTilesHaveIssues || _overpassHasIssues;
  bool get osmTilesHaveIssues => _osmTilesHaveIssues;
  bool get overpassHasIssues => _overpassHasIssues;
  bool get isWaitingForData => _isWaitingForData;
  bool get isTimedOut => _isTimedOut;
  bool get hasNoData => _hasNoData;
  bool get hasSuccess => _hasSuccess;
  bool get nodeLimitReached => _nodeLimitReached;
  
  NetworkStatusType get currentStatus {
    // Simple single-path status logic
    if (hasAnyIssues) return NetworkStatusType.issues;
    if (_isWaitingForData) return NetworkStatusType.waiting;
    if (_isTimedOut) return NetworkStatusType.timedOut;
    if (_hasNoData) return NetworkStatusType.noData;
    if (_hasSuccess) return NetworkStatusType.success;
    if (_nodeLimitReached) return NetworkStatusType.nodeLimitReached;
    return NetworkStatusType.ready;
  }

  NetworkIssueType? get currentIssueType {
    if (_osmTilesHaveIssues && _overpassHasIssues) return NetworkIssueType.both;
    if (_osmTilesHaveIssues) return NetworkIssueType.osmTiles;
    if (_overpassHasIssues) return NetworkIssueType.overpassApi;
    return null;
  }

  /// Report tile server issues (for any provider)
  void reportOsmTileIssue() {
    if (!_osmTilesHaveIssues) {
      _osmTilesHaveIssues = true;
      notifyListeners();
      debugPrint('[NetworkStatus] Tile server issues detected');
    }
    
    // Reset recovery timer - if we keep getting errors, keep showing indicator
    _osmRecoveryTimer?.cancel();
    _osmRecoveryTimer = Timer(const Duration(minutes: 2), () {
      _osmTilesHaveIssues = false;
      notifyListeners();
      debugPrint('[NetworkStatus] Tile server issues cleared');
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
      // Quietly clear - don't log routine success
      _osmTilesHaveIssues = false;
      _osmRecoveryTimer?.cancel();
      notifyListeners();
    }
  }

  void reportOverpassSuccess() {
    if (_overpassHasIssues) {
      // Quietly clear - don't log routine success
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
      // Don't log routine waiting - only log if we stay waiting too long
    }
    
    // Set timeout for genuine network issues (not 404s)
    _waitingTimer?.cancel();
    _waitingTimer = Timer(const Duration(seconds: 8), () {
      _isWaitingForData = false;
      _isTimedOut = true;
      debugPrint('[NetworkStatus] Request timed out - likely network issues');
      notifyListeners();
    });
  }
  
  /// Show success status briefly when data loads
  void setSuccess() {
    _isWaitingForData = false;
    _isTimedOut = false;
    _hasNoData = false;
    _hasSuccess = true;
    _recentOfflineMisses = 0;
    _waitingTimer?.cancel();
    _noDataResetTimer?.cancel();
    notifyListeners();
    
    // Auto-clear success status after 2 seconds
    _successResetTimer?.cancel();
    _successResetTimer = Timer(const Duration(seconds: 2), () {
      if (_hasSuccess) {
        _hasSuccess = false;
        notifyListeners();
      }
    });
  }

  /// Show no-data status briefly when tiles aren't available
  void setNoData() {
    _isWaitingForData = false;
    _isTimedOut = false;
    _hasSuccess = false;
    _hasNoData = true;
    _waitingTimer?.cancel();
    _successResetTimer?.cancel();
    notifyListeners();
    
    // Auto-clear no-data status after 2 seconds
    _noDataResetTimer?.cancel();
    _noDataResetTimer = Timer(const Duration(seconds: 2), () {
      if (_hasNoData) {
        _hasNoData = false;
        notifyListeners();
      }
    });
  }

  /// Clear waiting/timeout/no-data status (legacy method for compatibility)
  void clearWaiting() {
    if (_isWaitingForData || _isTimedOut || _hasNoData || _hasSuccess || _nodeLimitReached) {
      _isWaitingForData = false;
      _isTimedOut = false;
      _hasNoData = false;
      _hasSuccess = false;
      _nodeLimitReached = false;
      _recentOfflineMisses = 0;
      _waitingTimer?.cancel();
      _noDataResetTimer?.cancel();
      _successResetTimer?.cancel();
      _nodeLimitResetTimer?.cancel();
      notifyListeners();
    }
  }
  
  /// Set timeout error state
  void setTimeoutError() {
    _isWaitingForData = false;
    _isTimedOut = true;
    _hasNoData = false;
    _hasSuccess = false;
    _waitingTimer?.cancel();
    _noDataResetTimer?.cancel();
    _successResetTimer?.cancel();
    notifyListeners();
    debugPrint('[NetworkStatus] Request timed out');
    
    // Auto-clear timeout after 5 seconds
    Timer(const Duration(seconds: 5), () {
      if (_isTimedOut) {
        _isTimedOut = false;
        notifyListeners();
      }
    });
  }
  
  /// Set network error state (rate limits, connection issues, etc.)
  void setNetworkError() {
    _isWaitingForData = false;
    _isTimedOut = false;
    _hasNoData = false; 
    _hasSuccess = false;
    _waitingTimer?.cancel();
    _noDataResetTimer?.cancel();
    _successResetTimer?.cancel();
    
    // Use existing issue reporting system
    reportOverpassIssue();
    debugPrint('[NetworkStatus] Network error occurred');
  }
  
  /// Show notification that node display limit was reached
  void reportNodeLimitReached(int totalNodes, int maxNodes) {
    _nodeLimitReached = true;
    notifyListeners();
    debugPrint('[NetworkStatus] Node display limit reached: $totalNodes found, showing $maxNodes');
    
    // Auto-clear after 8 seconds
    _nodeLimitResetTimer?.cancel();
    _nodeLimitResetTimer = Timer(const Duration(seconds: 8), () {
      if (_nodeLimitReached) {
        _nodeLimitReached = false;
        notifyListeners();
      }
    });
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
    _successResetTimer?.cancel();
    _nodeLimitResetTimer?.cancel();
    super.dispose();
  }
}
import 'package:flutter/material.dart';
import 'dart:async';

import '../app_state.dart';

enum NetworkIssueType { overpassApi }
enum NetworkStatusType { waiting, issues, timedOut, noData, ready, success }



class NetworkStatus extends ChangeNotifier {
  static final NetworkStatus instance = NetworkStatus._();
  NetworkStatus._();

  bool _overpassHasIssues = false;
  bool _isWaitingForData = false;
  bool _isTimedOut = false;
  bool _hasNoData = false;
  bool _hasSuccess = false;
  int _recentOfflineMisses = 0;
  Timer? _overpassRecoveryTimer;
  Timer? _noDataResetTimer;
  Timer? _successResetTimer;
  // Getters
  bool get hasAnyIssues => _overpassHasIssues;
  bool get overpassHasIssues => _overpassHasIssues;
  bool get isWaitingForData => _isWaitingForData;
  bool get isTimedOut => _isTimedOut;
  bool get hasNoData => _hasNoData;
  bool get hasSuccess => _hasSuccess;
  
  NetworkStatusType get currentStatus {
    // Simple single-path status logic
    if (hasAnyIssues) return NetworkStatusType.issues;
    if (_isWaitingForData) return NetworkStatusType.waiting;
    if (_isTimedOut) return NetworkStatusType.timedOut;
    if (_hasNoData) return NetworkStatusType.noData;
    if (_hasSuccess) return NetworkStatusType.success;
    return NetworkStatusType.ready;
  }

  NetworkIssueType? get currentIssueType {
    if (_overpassHasIssues) return NetworkIssueType.overpassApi;
    return null;
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
  void reportOverpassSuccess() {
    if (_overpassHasIssues) {
      // Quietly clear - don't log routine success
      _overpassHasIssues = false;
      _overpassRecoveryTimer?.cancel();
      notifyListeners();
    }
  }

  /// Report that requests are taking longer than usual (splitting, backoffs, etc.)
  void reportSlowProgress() {
    if (!_overpassHasIssues) {
      _overpassHasIssues = true;
      _isWaitingForData = false; // Transition from waiting to slow progress
      notifyListeners();
      debugPrint('[NetworkStatus] Surveillance data requests taking longer than usual');
    }
    
    // Reset recovery timer - we'll clear this when the operation actually completes
    _overpassRecoveryTimer?.cancel();
    _overpassRecoveryTimer = Timer(const Duration(minutes: 2), () {
      _overpassHasIssues = false;
      notifyListeners();
      debugPrint('[NetworkStatus] Slow progress status cleared');
    });
  }

  /// Set waiting status (show when loading surveillance data)
  void setWaiting() {
    // Clear any previous timeout/no-data state when starting new wait
    _isTimedOut = false;
    _hasNoData = false;
    _recentOfflineMisses = 0;
    _noDataResetTimer?.cancel();
    
    if (!_isWaitingForData) {
      _isWaitingForData = true;
      notifyListeners();
    }
  }
  
  /// Show success status briefly when data loads
  void setSuccess() {
    _isWaitingForData = false;
    _isTimedOut = false;
    _hasNoData = false;
    _hasSuccess = true;
    _recentOfflineMisses = 0;
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
    if (_isWaitingForData || _isTimedOut || _hasNoData || _hasSuccess) {
      _isWaitingForData = false;
      _isTimedOut = false;
      _hasNoData = false;
      _hasSuccess = false;
      _recentOfflineMisses = 0;
      _noDataResetTimer?.cancel();
      _successResetTimer?.cancel();
      notifyListeners();
    }
  }
  
  /// Set timeout error state
  void setTimeoutError() {
    _isWaitingForData = false;
    _isTimedOut = true;
    _hasNoData = false;
    _hasSuccess = false;
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
    _noDataResetTimer?.cancel();
    _successResetTimer?.cancel();
    
    // Use existing issue reporting system
    reportOverpassIssue();
    debugPrint('[NetworkStatus] Network error occurred');
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
    _overpassRecoveryTimer?.cancel();
    _noDataResetTimer?.cancel();
    _successResetTimer?.cancel();
    super.dispose();
  }
}
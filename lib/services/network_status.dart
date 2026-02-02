import 'package:flutter/material.dart';
import 'dart:async';

/// Simple enum-based network status for surveillance data requests.
/// Only tracks the latest user-initiated request - background requests are ignored.
enum NetworkRequestStatus {
  idle,        // No active requests
  loading,     // Request in progress
  splitting,   // Request being split due to limits/timeouts
  success,     // Data loaded successfully
  timeout,     // Request timed out
  rateLimited, // API rate limited
  noData,      // No offline data available
  error,       // Other network errors
}

class NetworkStatus extends ChangeNotifier {
  static final NetworkStatus instance = NetworkStatus._();
  NetworkStatus._();

  NetworkRequestStatus _status = NetworkRequestStatus.idle;
  Timer? _autoResetTimer;
  
  /// Current network status
  NetworkRequestStatus get status => _status;
  
  /// Set status and handle auto-reset timers
  void _setStatus(NetworkRequestStatus newStatus) {
    if (_status == newStatus) return;
    
    _status = newStatus;
    _autoResetTimer?.cancel();
    
    // Auto-reset certain statuses after a delay
    switch (newStatus) {
      case NetworkRequestStatus.success:
        _autoResetTimer = Timer(const Duration(seconds: 2), () {
          _setStatus(NetworkRequestStatus.idle);
        });
        break;
      case NetworkRequestStatus.timeout:
      case NetworkRequestStatus.error:
        _autoResetTimer = Timer(const Duration(seconds: 5), () {
          _setStatus(NetworkRequestStatus.idle);
        });
        break;
      case NetworkRequestStatus.noData:
        _autoResetTimer = Timer(const Duration(seconds: 3), () {
          _setStatus(NetworkRequestStatus.idle);
        });
        break;
      case NetworkRequestStatus.rateLimited:
        _autoResetTimer = Timer(const Duration(minutes: 2), () {
          _setStatus(NetworkRequestStatus.idle);
        });
        break;
      default:
        // No auto-reset for idle, loading, splitting
        break;
    }
    
    notifyListeners();
  }

  /// Start loading surveillance data
  void setLoading() {
    debugPrint('[NetworkStatus] Loading surveillance data');
    _setStatus(NetworkRequestStatus.loading);
  }
  
  /// Request is being split due to complexity/limits
  void setSplitting() {
    debugPrint('[NetworkStatus] Splitting request due to complexity');
    _setStatus(NetworkRequestStatus.splitting);
  }
  
  /// Data loaded successfully
  void setSuccess() {
    debugPrint('[NetworkStatus] Surveillance data loaded successfully');
    _setStatus(NetworkRequestStatus.success);
  }
  
  /// Request timed out
  void setTimeout() {
    debugPrint('[NetworkStatus] Request timed out');
    _setStatus(NetworkRequestStatus.timeout);
  }
  
  /// Rate limited by API
  void setRateLimited() {
    debugPrint('[NetworkStatus] Rate limited by API');
    _setStatus(NetworkRequestStatus.rateLimited);
  }
  
  /// No offline data available
  void setNoData() {
    debugPrint('[NetworkStatus] No offline data available');
    _setStatus(NetworkRequestStatus.noData);
  }
  
  /// Network or other error
  void setError() {
    debugPrint('[NetworkStatus] Network error occurred');
    _setStatus(NetworkRequestStatus.error);
  }
  
  /// Clear status (force to idle)
  void clear() {
    _setStatus(NetworkRequestStatus.idle);
  }

  @override
  void dispose() {
    _autoResetTimer?.cancel();
    super.dispose();
  }
}
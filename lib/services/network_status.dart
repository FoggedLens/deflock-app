import 'package:flutter/material.dart';
import 'dart:async';

enum NetworkIssueType { osmTiles, overpassApi, both }

class NetworkStatus extends ChangeNotifier {
  static final NetworkStatus instance = NetworkStatus._();
  NetworkStatus._();

  bool _osmTilesHaveIssues = false;
  bool _overpassHasIssues = false;
  Timer? _osmRecoveryTimer;
  Timer? _overpassRecoveryTimer;

  // Getters
  bool get hasAnyIssues => _osmTilesHaveIssues || _overpassHasIssues;
  bool get osmTilesHaveIssues => _osmTilesHaveIssues;
  bool get overpassHasIssues => _overpassHasIssues;

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

  @override
  void dispose() {
    _osmRecoveryTimer?.cancel();
    _overpassRecoveryTimer?.cancel();
    super.dispose();
  }
}
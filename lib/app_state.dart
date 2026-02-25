import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'services/http_client.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/node_profile.dart';
import 'models/operator_profile.dart';
import 'models/osm_node.dart';
import 'models/pending_upload.dart';
import 'models/suspected_location.dart';
import 'models/tile_provider.dart';
import 'models/search_result.dart';
import 'services/nuclear_reset_service.dart';
import 'services/offline_area_service.dart';
import 'services/map_data_provider.dart';
import 'services/node_data_manager.dart';
import 'services/tile_preview_service.dart';
import 'services/changelog_service.dart';
import 'services/operator_profile_service.dart';
import 'services/deep_link_service.dart';
import 'widgets/node_provider_with_cache.dart';
import 'services/profile_service.dart';
import 'widgets/reauth_messages_dialog.dart';
import 'dev_config.dart';
import 'state/auth_state.dart';
import 'state/messages_state.dart';
import 'state/navigation_state.dart';
import 'state/operator_profile_state.dart';
import 'state/profile_state.dart';
import 'state/search_state.dart';
import 'state/session_state.dart';
import 'state/settings_state.dart';
import 'state/suspected_location_state.dart';
import 'state/upload_queue_state.dart';

// Re-export types
export 'state/navigation_state.dart' show AppNavigationMode;
export 'state/settings_state.dart' show UploadMode, FollowMeMode;
export 'state/session_state.dart' show AddNodeSession, EditNodeSession;
export 'models/pending_upload.dart' show UploadOperation;

// ------------------ AppState ------------------
class AppState extends ChangeNotifier {
  static late AppState instance;
  
  // State modules
  late final AuthState _authState;
  late final MessagesState _messagesState;
  late final NavigationState _navigationState;
  late final OperatorProfileState _operatorProfileState;
  late final ProfileState _profileState;
  late final SearchState _searchState;
  late final SessionState _sessionState;
  late final SettingsState _settingsState;
  late final SuspectedLocationState _suspectedLocationState;
  late final UploadQueueState _uploadQueueState;

  bool _isInitialized = false;
  
  // Positioning tutorial state
  LatLng? _tutorialStartPosition; // Track where the tutorial started
  VoidCallback? _tutorialCompletionCallback; // Callback when tutorial is completed
  Timer? _messageCheckTimer;

  AppState() {
    instance = this;
    _authState = AuthState();
    _messagesState = MessagesState();
    _navigationState = NavigationState();
    _operatorProfileState = OperatorProfileState();
    _profileState = ProfileState();
    _searchState = SearchState();
    _sessionState = SessionState();
    _settingsState = SettingsState();
    _suspectedLocationState = SuspectedLocationState();
    _uploadQueueState = UploadQueueState();
    
    // Set up state change listeners
    _authState.addListener(_onStateChanged);
    _messagesState.addListener(_onStateChanged);
    _navigationState.addListener(_onStateChanged);
    _operatorProfileState.addListener(_onStateChanged);
    _profileState.addListener(_onStateChanged);
    _searchState.addListener(_onStateChanged);
    _sessionState.addListener(_onStateChanged);
    _settingsState.addListener(_onStateChanged);
    _suspectedLocationState.addListener(_onStateChanged);
    _uploadQueueState.addListener(_onStateChanged);
    
    _init();
  }

  // Getters that delegate to individual state modules
  bool get isInitialized => _isInitialized;
  
  // Auth state
  bool get isLoggedIn => _authState.isLoggedIn;
  String get username => _authState.username;
  
  // Navigation state - simplified
  AppNavigationMode get navigationMode => _navigationState.mode;
  LatLng? get provisionalPinLocation => _navigationState.provisionalPinLocation;
  String? get provisionalPinAddress => _navigationState.provisionalPinAddress;
  bool get showProvisionalPin => _navigationState.showProvisionalPin;
  bool get isInSearchMode => _navigationState.isInSearchMode;
  bool get isInRouteMode => _navigationState.isInRouteMode;
  bool get hasActiveRoute => _navigationState.hasActiveRoute;
  bool get showSearchButton => _navigationState.showSearchButton;
  bool get showRouteButton => _navigationState.showRouteButton;
  List<LatLng>? get routePath => _navigationState.routePath;
  
  // Route state
  LatLng? get routeStart => _navigationState.routeStart;
  LatLng? get routeEnd => _navigationState.routeEnd;
  String? get routeStartAddress => _navigationState.routeStartAddress;
  String? get routeEndAddress => _navigationState.routeEndAddress;
  double? get routeDistance => _navigationState.routeDistance;
  bool get settingRouteStart => _navigationState.settingRouteStart;
  bool get isSettingSecondPoint => _navigationState.isSettingSecondPoint;
  bool get areRoutePointsTooClose => _navigationState.areRoutePointsTooClose;
  double? get distanceFromFirstPoint => _navigationState.distanceFromFirstPoint;
  bool get distanceExceedsWarningThreshold => _navigationState.distanceExceedsWarningThreshold;
  bool get isCalculating => _navigationState.isCalculating;
  bool get showingOverview => _navigationState.showingOverview;
  String? get routingError => _navigationState.routingError;
  bool get hasRoutingError => _navigationState.hasRoutingError;
  
  // Navigation search state
  bool get isNavigationSearchLoading => _navigationState.isSearchLoading;
  List<SearchResult> get navigationSearchResults => _navigationState.searchResults;
  int get navigationAvoidanceDistance => _settingsState.navigationAvoidanceDistance;
  DistanceUnit get distanceUnit => _settingsState.distanceUnit;
  
  // Profile state
  List<NodeProfile> get profiles => _profileState.profiles;
  List<NodeProfile> get enabledProfiles => _profileState.enabledProfiles;
  bool isEnabled(NodeProfile p) => _profileState.isEnabled(p);
  
  // Operator profile state
  List<OperatorProfile> get operatorProfiles => _operatorProfileState.profiles;
  
  // Search state
  bool get isSearchLoading => _searchState.isLoading;
  List<SearchResult> get searchResults => _searchState.results;
  String get lastSearchQuery => _searchState.lastQuery;
  
  // Session state
  AddNodeSession? get session => _sessionState.session;
  EditNodeSession? get editSession => _sessionState.editSession;
  
  // Settings state
  bool get offlineMode => _settingsState.offlineMode;
  bool get pauseQueueProcessing => _settingsState.pauseQueueProcessing;
  int get maxNodes => _settingsState.maxNodes;
  UploadMode get uploadMode => _settingsState.uploadMode;
  FollowMeMode get followMeMode => _settingsState.followMeMode;

  bool get proximityAlertsEnabled => _settingsState.proximityAlertsEnabled;
  int get proximityAlertDistance => _settingsState.proximityAlertDistance;
  bool get networkStatusIndicatorEnabled => _settingsState.networkStatusIndicatorEnabled;
  int get suspectedLocationMinDistance => _settingsState.suspectedLocationMinDistance;
  
  // Messages state
  int? get unreadMessageCount => _messagesState.unreadCount;
  bool get hasUnreadMessages => _messagesState.hasUnreadMessages;
  bool get isCheckingMessages => _messagesState.isChecking;
  
  // Tile provider state
  List<TileProvider> get tileProviders => _settingsState.tileProviders;
  TileType? get selectedTileType => _settingsState.selectedTileType;
  TileProvider? get selectedTileProvider => _settingsState.selectedTileProvider;
  

  
  // Upload queue state
  int get pendingCount => _uploadQueueState.pendingCount;
  List<PendingUpload> get pendingUploads => _uploadQueueState.pendingUploads;

  // Suspected location state
  SuspectedLocation? get selectedSuspectedLocation => _suspectedLocationState.selectedLocation;
  bool get suspectedLocationsEnabled => _suspectedLocationState.isEnabled;
  bool get suspectedLocationsLoading => _suspectedLocationState.isLoading;
  double? get suspectedLocationsDownloadProgress => _suspectedLocationState.downloadProgress;
  Future<DateTime?> get suspectedLocationsLastFetch => _suspectedLocationState.lastFetchTime;

  void _onStateChanged() {
    notifyListeners();
  }

  // ---------- Init ----------
  static const String _initFailureCountKey = 'init_failure_count';

  Future<void> _init() async {
    try {
      // Nuclear reset check: if init has failed >= 2 times, wipe everything
      final prefs = await SharedPreferences.getInstance();
      final failureCount = prefs.getInt(_initFailureCountKey) ?? 0;
      if (failureCount >= 2) {
        debugPrint('[AppState] Init failed $failureCount times — triggering nuclear reset');
        await NuclearResetService.clearEverything();
        // clearEverything() wipes SharedPreferences, so re-acquire the instance
      }

      // Increment failure count before running init (cleared on success).
      // Re-read from prefs in case nuclear reset just wiped the old value.
      final prefsForCount = await SharedPreferences.getInstance();
      final currentCount = prefsForCount.getInt(_initFailureCountKey) ?? 0;
      await prefsForCount.setInt(_initFailureCountKey, currentCount + 1);

      // Settings must init first — other modules read its values
      await _settingsState.init();

      // Initialize changelog service
      await ChangelogService().init();

      // Fire-and-forget tile preview fetch (existing pattern)
      _fetchMissingTilePreviews();

      // Check if we should add default profiles (first launch OR no profiles of each type exist)
      const firstLaunchKey = 'profiles_defaults_initialized';
      final prefsForProfiles = await SharedPreferences.getInstance();
      final isFirstLaunch = !(prefsForProfiles.getBool(firstLaunchKey) ?? false);

      final existingOperatorProfiles = await OperatorProfileService().load();
      final existingNodeProfiles = await ProfileService().load();

      final shouldAddOperatorDefaults = isFirstLaunch || existingOperatorProfiles.isEmpty;
      final shouldAddNodeDefaults = isFirstLaunch || existingNodeProfiles.isEmpty;

      await _operatorProfileState.init(addDefaults: shouldAddOperatorDefaults);
      await _profileState.init(addDefaults: shouldAddNodeDefaults);

      // Set up callback to clear stale sessions when profiles are deleted
      _profileState.setProfileDeletedCallback(_onProfileDeleted);

      if (isFirstLaunch) {
        await prefsForProfiles.setBool(firstLaunchKey, true);
      }

      // Local-only init for suspected locations (no network)
      await _suspectedLocationState.initLocal();
      await _uploadQueueState.init();
      // Local-only auth init (no network)
      await _authState.init(_settingsState.uploadMode);

      // Set up callback to repopulate pending nodes after cache clears
      NodeProviderWithCache.instance.setOnCacheClearedCallback(() {
        _uploadQueueState.repopulateCacheFromQueue();
      });

      // Initialize OfflineAreaService to ensure offline areas are loaded
      await OfflineAreaService().ensureInitialized();

      // Preload offline nodes into cache for immediate display
      await NodeDataManager().preloadOfflineNodes();

      // Start uploader if conditions are met
      _startUploader();

      _isInitialized = true;

      // Clear failure count on success
      final prefsForClear = await SharedPreferences.getInstance();
      await prefsForClear.setInt(_initFailureCountKey, 0);

      // Post-init background tasks (non-blocking, fire-and-forget)
      _suspectedLocationState.refreshIfNeeded(
        offlineMode: _settingsState.offlineMode,
      );
      _authState.refreshIfNeeded();
      if (isLoggedIn) checkMessages();
      _startMessageCheckTimer();
      Future.delayed(const Duration(milliseconds: 500), () {
        DeepLinkService().checkInitialLink();
      });

      notifyListeners();
    } catch (e, stackTrace) {
      debugPrint('[AppState] Critical error during initialization: $e');
      debugPrint('[AppState] Stack trace: $stackTrace');
      // Set initialized to true to prevent stuck loading screen.
      // Next launch may trigger nuclear reset if failure count >= 2.
      _isInitialized = true;
      notifyListeners();
    }
  }
  
  void _startMessageCheckTimer() {
    _messageCheckTimer?.cancel();
    
    // Check messages every 10 minutes when logged in
    _messageCheckTimer = Timer.periodic(
      const Duration(minutes: 10),
      (timer) {
        if (isLoggedIn) {
          checkMessages();
        }
      },
    );
  }

  // ---------- Auth Methods ----------
  Future<void> login() async {
    await _authState.login();
    // Check for messages after successful login
    if (isLoggedIn) {
      checkMessages();
    }
  }

  Future<void> logout() async {
    await _authState.logout();
    // Clear message state when logging out
    clearMessages();
  }

  Future<void> refreshAuthState() async {
    await _authState.refreshAuthState();
  }

  Future<void> forceLogin() async {
    await _authState.forceLogin();
    // Check for messages after successful login
    if (isLoggedIn) {
      checkMessages();
    }
  }

  Future<bool> validateToken() async {
    try {
      await _authState.refreshAuthState();
      return _authState.isLoggedIn;
    } catch (e) {
      debugPrint('AppState: Token validation error: $e');
      return false;
    }
  }
  
  // ---------- Messages Methods ----------
  Future<void> checkMessages({bool forceRefresh = false}) async {
    final accessToken = await _authState.getAccessToken();
    await _messagesState.checkMessages(
      accessToken: accessToken,
      uploadMode: uploadMode,
      forceRefresh: forceRefresh,
    );
  }
  
  String getMessagesUrl() {
    return _messagesState.getMessagesUrl(uploadMode);
  }
  
  void clearMessages() {
    _messagesState.clearMessages();
  }
  
  /// Check if the current OAuth token has required scopes for message notifications
  /// Returns true if re-authentication is needed
  Future<bool> needsReauthForMessages() async {
    // Only check if logged in and not in simulate mode
    if (!isLoggedIn || uploadMode == UploadMode.simulate) {
      return false;
    }
    
    final accessToken = await _authState.getAccessToken();
    if (accessToken == null) return false;
    
    final client = UserAgentClient();
    try {
      // Try to fetch user details - this should include message data if scope is correct
      final response = await client.get(
        Uri.parse('${_getApiHost()}/api/0.6/user/details.json'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 403) {
        // Forbidden - likely missing scope
        return true;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = data['user']?['messages'];
        // If messages field is missing, we might not have the right scope
        return messages == null;
      }

      return false;
    } catch (e) {
      // On error, assume no re-auth needed to avoid annoying users
      return false;
    } finally {
      client.close();
    }
  }
  
  /// Show re-authentication dialog if needed
  Future<void> checkAndPromptReauthForMessages(BuildContext context) async {
    if (await needsReauthForMessages()) {
      if (!context.mounted) return;
      _showReauthDialog(context);
    }
  }
  
  void _showReauthDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ReauthMessagesDialog(
        onReauth: () {
          // Navigate to OSM account page where user can re-authenticate
          Navigator.of(context).pushNamed('/settings/osm-account');
        },
        onDismiss: () {
          // Just dismiss - will show again on next app start or mode change
        },
      ),
    );
  }
  
  String _getApiHost() {
    switch (uploadMode) {
      case UploadMode.production:
        return 'https://api.openstreetmap.org';
      case UploadMode.sandbox:
        return 'https://api06.dev.openstreetmap.org';
      case UploadMode.simulate:
        return 'https://api.openstreetmap.org';
    }
  }

  // ---------- Profile Methods ----------
  void toggleProfile(NodeProfile p, bool e) {
    _profileState.toggleProfile(p, e);
  }

  void addOrUpdateProfile(NodeProfile p) {
    _profileState.addOrUpdateProfile(p);
  }

  void deleteProfile(NodeProfile p) {
    _profileState.deleteProfile(p);
  }
  
  // Callback when a profile is deleted - clear any stale session references
  void _onProfileDeleted(NodeProfile deletedProfile) {
    // Clear add session if it references the deleted profile
    if (_sessionState.session?.profile?.id == deletedProfile.id) {
      cancelSession();
    }
    
    // Clear edit session if it references the deleted profile  
    if (_sessionState.editSession?.profile?.id == deletedProfile.id) {
      cancelEditSession();
    }
  }

  // ---------- Operator Profile Methods ----------
  void addOrUpdateOperatorProfile(OperatorProfile p) {
    _operatorProfileState.addOrUpdateProfile(p);
  }

  void deleteOperatorProfile(OperatorProfile p) {
    _operatorProfileState.deleteProfile(p);
  }

  // ---------- Session Methods ----------
  void startAddSession() {
    _sessionState.startAddSession(enabledProfiles);
  }

  void startEditSession(OsmNode node) {
    _sessionState.startEditSession(node, enabledProfiles, operatorProfiles);
  }

  void updateSession({
    double? directionDeg,
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
    LatLng? target,
    Map<String, String>? refinedTags,
    Map<String, String>? additionalExistingTags,
    String? changesetComment,
    bool updateOperatorProfile = false,
  }) {
    _sessionState.updateSession(
      directionDeg: directionDeg,
      profile: profile,
      operatorProfile: operatorProfile,
      target: target,
      refinedTags: refinedTags,
      additionalExistingTags: additionalExistingTags,
      changesetComment: changesetComment,
      updateOperatorProfile: updateOperatorProfile,
    );
    
    // Check tutorial completion if position changed
    if (target != null) {
      _checkTutorialCompletion(target);
    }
  }

  void updateEditSession({
    double? directionDeg,
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
    LatLng? target,
    bool? extractFromWay,
    Map<String, String>? refinedTags,
    Map<String, String>? additionalExistingTags,
    String? changesetComment,
    bool updateOperatorProfile = false,
  }) {
    _sessionState.updateEditSession(
      directionDeg: directionDeg,
      profile: profile,
      operatorProfile: operatorProfile,
      target: target,
      extractFromWay: extractFromWay,
      refinedTags: refinedTags,
      additionalExistingTags: additionalExistingTags,
      changesetComment: changesetComment,
      updateOperatorProfile: updateOperatorProfile,
    );
    
    // Check tutorial completion if position changed
    if (target != null) {
      _checkTutorialCompletion(target);
    }
  }
  
  // For map view to check for pending snap backs
  LatLng? consumePendingSnapBack() {
    return _sessionState.consumePendingSnapBack();
  }

  // Positioning tutorial methods
  void registerTutorialCallback(VoidCallback onComplete) {
    _tutorialCompletionCallback = onComplete;
    // Record the starting position when tutorial begins
    if (session?.target != null) {
      _tutorialStartPosition = session!.target;
    } else if (editSession?.target != null) {
      _tutorialStartPosition = editSession!.target;
    }
  }

  void clearTutorialCallback() {
    _tutorialCompletionCallback = null;
    _tutorialStartPosition = null;
  }

  void _checkTutorialCompletion(LatLng newPosition) {
    if (_tutorialCompletionCallback == null || _tutorialStartPosition == null) return;
    
    // Calculate distance moved
    final distance = Distance();
    final distanceMoved = distance.as(LengthUnit.Meter, _tutorialStartPosition!, newPosition);
    
    if (distanceMoved >= kPositioningTutorialMinMovementMeters) {
      // Tutorial completed! Mark as complete and notify callback immediately
      final callback = _tutorialCompletionCallback;
      clearTutorialCallback();
      callback?.call();
      
      // Mark as complete in background (don't await to avoid delays)
      ChangelogService().markPositioningTutorialCompleted();
    }
  }

  void addDirection() {
    _sessionState.addDirection();
  }

  void removeDirection() {
    _sessionState.removeDirection();
  }

  bool get canRemoveDirection => _sessionState.canRemoveDirection;

  void cycleDirection() {
    _sessionState.cycleDirection();
  }



  void cancelSession() {
    _sessionState.cancelSession();
  }

  void cancelEditSession() {
    _sessionState.cancelEditSession();
  }

  void commitSession() {
    final session = _sessionState.commitSession();
    if (session != null) {
      _uploadQueueState.addFromSession(session, uploadMode: uploadMode);
      _startUploader();
    }
  }

  void commitEditSession() {
    final session = _sessionState.commitEditSession();
    if (session != null) {
      _uploadQueueState.addFromEditSession(session, uploadMode: uploadMode);
      _startUploader();
    }
  }

  void deleteNode(OsmNode node) {
    _uploadQueueState.addFromNodeDeletion(node, uploadMode: uploadMode);
    _startUploader();
  }

  // ---------- Search Methods ----------
  Future<void> search(String query) async {
    await _searchState.search(query);
  }

  void clearSearchResults() {
    _searchState.clearResults();
  }

  // ---------- Navigation Methods - Simplified ----------
  void enterSearchMode(LatLng mapCenter, {LatLngBounds? viewbox}) {
    _navigationState.enterSearchMode(mapCenter, viewbox: viewbox);
  }

  void cancelNavigation() {
    _navigationState.cancel();
  }

  void updateProvisionalPinLocation(LatLng newLocation) {
    _navigationState.updateProvisionalPinLocation(newLocation);
  }

  void selectSearchResult(SearchResult result) {
    _navigationState.selectSearchResult(result);
  }

  void startRoutePlanning({required bool thisLocationIsStart}) {
    _navigationState.startRoutePlanning(thisLocationIsStart: thisLocationIsStart);
  }

  void selectSecondRoutePoint() {
    _navigationState.selectSecondRoutePoint();
  }

  void startRoute() {
    _navigationState.startRoute();
    
    // Auto-enable follow-me if user is near the start point
    // We need to get user location from the GPS controller
    // This will be handled in HomeScreen where we have access to MapView
  }
  
  bool shouldAutoEnableFollowMe(LatLng? userLocation) {
    return _navigationState.shouldAutoEnableFollowMe(userLocation);
  }

  void showRouteOverview() {
    _navigationState.showRouteOverview();
  }

  void hideRouteOverview() {
    _navigationState.hideRouteOverview();
  }

  void cancelRoute() {
    _navigationState.cancelRoute();
  }

  // Navigation search methods
  Future<void> searchNavigation(String query) async {
    await _navigationState.search(query);
  }

  void clearNavigationSearchResults() {
    _navigationState.clearSearchResults();
  }

  void retryRouteCalculation() {
    _navigationState.retryRouteCalculation();
  }

  // ---------- Settings Methods ----------
  Future<void> setOfflineMode(bool enabled) async {
    await _settingsState.setOfflineMode(enabled);
    if (!enabled) {
      _startUploader(); // Resume upload queue processing as we leave offline mode
    } else {
      _uploadQueueState.stopUploader(); // Stop uploader in offline mode
      // Cancel any active area downloads
      await OfflineAreaService().cancelActiveDownloads();
    }
  }

  Future<void> setPauseQueueProcessing(bool enabled) async {
    await _settingsState.setPauseQueueProcessing(enabled);
    if (!enabled) {
      _startUploader(); // Resume upload queue processing
    } else {
      _uploadQueueState.stopUploader(); // Stop uploader when paused
    }
  }

  set maxNodes(int n) {
    _settingsState.maxNodes = n;
  }

  Future<void> setUploadMode(UploadMode mode) async {
    // Clear node cache when switching upload modes to prevent mixing production/sandbox data
    MapDataProvider().clearCache();
    debugPrint('[AppState] Cleared node cache due to upload mode change');
    
    await _settingsState.setUploadMode(mode);
    await _authState.onUploadModeChanged(mode);
    
    // Clear and re-check messages for new mode
    clearMessages();
    if (isLoggedIn) {
      // Don't await - let it run in background
      checkMessages();
      
      // Note: Re-auth check will be triggered from the settings screen after mode change
    }
    
    _startUploader(); // Restart uploader with new mode
  }

  /// Select a tile type by ID
  Future<void> setSelectedTileType(String tileTypeId) async {
    await _settingsState.setSelectedTileType(tileTypeId);
  }

  /// Add or update a tile provider
  Future<void> addOrUpdateTileProvider(TileProvider provider) async {
    await _settingsState.addOrUpdateTileProvider(provider);
  }

  /// Delete a tile provider
  Future<void> deleteTileProvider(String providerId) async {
    await _settingsState.deleteTileProvider(providerId);
  }

  /// Set follow-me mode
  Future<void> setFollowMeMode(FollowMeMode mode) async {
    await _settingsState.setFollowMeMode(mode);
  }
  
  /// Set proximity alerts enabled/disabled
  Future<void> setProximityAlertsEnabled(bool enabled) async {
    await _settingsState.setProximityAlertsEnabled(enabled);
  }

  /// Set proximity alert distance
  Future<void> setProximityAlertDistance(int distance) async {
    await _settingsState.setProximityAlertDistance(distance);
  }

  /// Set network status indicator enabled/disabled
  Future<void> setNetworkStatusIndicatorEnabled(bool enabled) async {
    await _settingsState.setNetworkStatusIndicatorEnabled(enabled);
  }



  /// Set suspected location minimum distance from real nodes
  Future<void> setSuspectedLocationMinDistance(int distance) async {
    await _settingsState.setSuspectedLocationMinDistance(distance);
  }

  /// Set navigation avoidance distance
  Future<void> setNavigationAvoidanceDistance(int distance) async {
    await _settingsState.setNavigationAvoidanceDistance(distance);
  }

  Future<void> setDistanceUnit(DistanceUnit unit) async {
    await _settingsState.setDistanceUnit(unit);
  }

  // ---------- Queue Methods ----------
  void clearQueue() {
    _uploadQueueState.clearQueue();
  }
  
  void removeFromQueue(PendingUpload upload) {
    _uploadQueueState.removeFromQueue(upload);
  }

  void retryUpload(PendingUpload upload) {
    _uploadQueueState.retryUpload(upload);
    _startUploader(); // resume uploader if not busy
  }

  /// Reload upload queue from storage (for migration purposes)
  Future<void> reloadUploadQueue() async {
    await _uploadQueueState.reloadQueue();
  }

  // ---------- Suspected Location Methods ----------
  Future<void> setSuspectedLocationsEnabled(bool enabled) async {
    await _suspectedLocationState.setEnabled(enabled);
  }

  Future<bool> refreshSuspectedLocations() async {
    return await _suspectedLocationState.refreshData();
  }

  Future<void> reinitSuspectedLocations() async {
    await _suspectedLocationState.init(offlineMode: _settingsState.offlineMode);
  }

  void selectSuspectedLocation(SuspectedLocation location) {
    _suspectedLocationState.selectLocation(location);
  }

  void clearSuspectedLocationSelection() {
    _suspectedLocationState.clearSelection();
  }

  Future<List<SuspectedLocation>> getSuspectedLocationsInBounds({
    required double north,
    required double south,
    required double east,
    required double west,
  }) async {
    return await _suspectedLocationState.getLocationsInBounds(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }
  
  List<SuspectedLocation> getSuspectedLocationsInBoundsSync({
    required double north,
    required double south,
    required double east,
    required double west,
  }) {
    return _suspectedLocationState.getLocationsInBoundsSync(
      north: north,
      south: south,
      east: east,
      west: west,
    );
  }

  // ---------- Utility Methods ----------

  /// Generate a default changeset comment for a submission
  /// Handles special case of `<Existing tags>` profile by using "a" instead
  static String generateDefaultChangesetComment({
    required NodeProfile? profile,
    required UploadOperation operation,
  }) {
    // Handle temp profiles with brackets by using "a"
    final profileName = profile?.name.startsWith('<') == true && profile?.name.endsWith('>') == true
        ? 'a'
        : profile?.name ?? 'surveillance';
    
    switch (operation) {
      case UploadOperation.create:
        return 'Add $profileName surveillance node';
      case UploadOperation.modify:
        return 'Update $profileName surveillance node'; 
      case UploadOperation.delete:
        return 'Delete $profileName surveillance node';
      case UploadOperation.extract:
        return 'Extract $profileName surveillance node';
    }
  }

  // ---------- Private Methods ----------
  /// Attempts to fetch missing tile preview images in the background (fire and forget)
  void _fetchMissingTilePreviews() {
    // Run asynchronously without awaiting to avoid blocking app startup
    TilePreviewService.fetchMissingPreviews(_settingsState).catchError((error) {
      // Silently ignore errors - this is best effort
      debugPrint('AppState: Tile preview fetching failed silently: $error');
    });
  }

  void _startUploader() {
    _uploadQueueState.startUploader(
      offlineMode: offlineMode,
      pauseQueueProcessing: pauseQueueProcessing,
      uploadMode: uploadMode,
      getAccessToken: _authState.getAccessToken,
    );
  }

  @override
  void dispose() {
    _messageCheckTimer?.cancel();
    _authState.removeListener(_onStateChanged);
    _messagesState.removeListener(_onStateChanged);
    _navigationState.removeListener(_onStateChanged);
    _operatorProfileState.removeListener(_onStateChanged);
    _profileState.removeListener(_onStateChanged);
    _searchState.removeListener(_onStateChanged);
    _sessionState.removeListener(_onStateChanged);
    _settingsState.removeListener(_onStateChanged);
    _suspectedLocationState.removeListener(_onStateChanged);
    _uploadQueueState.removeListener(_onStateChanged);
    
    _uploadQueueState.dispose();
    super.dispose();
  }
}

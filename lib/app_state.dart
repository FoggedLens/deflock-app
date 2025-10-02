import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'models/node_profile.dart';
import 'models/operator_profile.dart';
import 'models/osm_node.dart';
import 'models/pending_upload.dart';
import 'models/tile_provider.dart';
import 'models/search_result.dart';
import 'services/offline_area_service.dart';
import 'services/node_cache.dart';
import 'services/tile_preview_service.dart';
import 'widgets/camera_provider_with_cache.dart';
import 'state/auth_state.dart';
import 'state/navigation_state.dart';
import 'state/operator_profile_state.dart';
import 'state/profile_state.dart';
import 'state/search_state.dart';
import 'state/session_state.dart';
import 'state/settings_state.dart';
import 'state/upload_queue_state.dart';

// Re-export types
export 'state/navigation_state.dart' show AppNavigationMode;
export 'state/settings_state.dart' show UploadMode, FollowMeMode;
export 'state/session_state.dart' show AddNodeSession, EditNodeSession;

// ------------------ AppState ------------------
class AppState extends ChangeNotifier {
  static late AppState instance;
  
  // State modules
  late final AuthState _authState;
  late final NavigationState _navigationState;
  late final OperatorProfileState _operatorProfileState;
  late final ProfileState _profileState;
  late final SearchState _searchState;
  late final SessionState _sessionState;
  late final SettingsState _settingsState;
  late final UploadQueueState _uploadQueueState;

  bool _isInitialized = false;

  AppState() {
    instance = this;
    _authState = AuthState();
    _navigationState = NavigationState();
    _operatorProfileState = OperatorProfileState();
    _profileState = ProfileState();
    _searchState = SearchState();
    _sessionState = SessionState();
    _settingsState = SettingsState();
    _uploadQueueState = UploadQueueState();
    
    // Set up state change listeners
    _authState.addListener(_onStateChanged);
    _navigationState.addListener(_onStateChanged);
    _operatorProfileState.addListener(_onStateChanged);
    _profileState.addListener(_onStateChanged);
    _searchState.addListener(_onStateChanged);
    _sessionState.addListener(_onStateChanged);
    _settingsState.addListener(_onStateChanged);
    _uploadQueueState.addListener(_onStateChanged);
    
    _init();
  }

  // Getters that delegate to individual state modules
  bool get isInitialized => _isInitialized;
  
  // Auth state
  bool get isLoggedIn => _authState.isLoggedIn;
  String get username => _authState.username;
  
  // Navigation state
  AppNavigationMode get navigationMode => _navigationState.mode;
  LatLng? get provisionalPinLocation => _navigationState.provisionalPinLocation;
  String? get provisionalPinAddress => _navigationState.provisionalPinAddress;
  bool get showProvisionalPin => _navigationState.showProvisionalPin;
  bool get isInSearchMode => _navigationState.isInSearchMode;
  bool get isInRouteMode => _navigationState.isInRouteMode;
  bool get hasActiveRoute => _navigationState.hasActiveRoute;
  List<LatLng>? get routePath => _navigationState.routePath;
  
  // Route state
  LatLng? get routeStart => _navigationState.routeStart;
  LatLng? get routeEnd => _navigationState.routeEnd;
  String? get routeStartAddress => _navigationState.routeStartAddress;
  String? get routeEndAddress => _navigationState.routeEndAddress;
  double? get routeDistance => _navigationState.routeDistance;
  bool get settingRouteStart => _navigationState.settingRouteStart;
  
  // Navigation search state
  bool get isNavigationSearchLoading => _navigationState.isSearchLoading;
  List<SearchResult> get navigationSearchResults => _navigationState.searchResults;
  
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
  int get maxCameras => _settingsState.maxCameras;
  UploadMode get uploadMode => _settingsState.uploadMode;
  FollowMeMode get followMeMode => _settingsState.followMeMode;
  bool get proximityAlertsEnabled => _settingsState.proximityAlertsEnabled;
  int get proximityAlertDistance => _settingsState.proximityAlertDistance;
  bool get networkStatusIndicatorEnabled => _settingsState.networkStatusIndicatorEnabled;
  
  // Tile provider state
  List<TileProvider> get tileProviders => _settingsState.tileProviders;
  TileType? get selectedTileType => _settingsState.selectedTileType;
  TileProvider? get selectedTileProvider => _settingsState.selectedTileProvider;
  

  
  // Upload queue state
  int get pendingCount => _uploadQueueState.pendingCount;
  List<PendingUpload> get pendingUploads => _uploadQueueState.pendingUploads;

  void _onStateChanged() {
    notifyListeners();
  }

  // ---------- Init ----------
  Future<void> _init() async {
    // Initialize all state modules
    await _settingsState.init();
    
    // Attempt to fetch missing tile type preview tiles (fails silently)
    _fetchMissingTilePreviews();
    
    await _operatorProfileState.init();
    await _profileState.init();
    await _uploadQueueState.init();
    await _authState.init(_settingsState.uploadMode);
    
    // Initialize OfflineAreaService to ensure offline areas are loaded
    await OfflineAreaService().ensureInitialized();
    
    // Start uploader if conditions are met
    _startUploader();
    
    _isInitialized = true;
    notifyListeners();
  }

  // ---------- Auth Methods ----------
  Future<void> login() async {
    await _authState.login();
  }

  Future<void> logout() async {
    await _authState.logout();
  }

  Future<void> refreshAuthState() async {
    await _authState.refreshAuthState();
  }

  Future<void> forceLogin() async {
    await _authState.forceLogin();
  }

  Future<bool> validateToken() async {
    return await _authState.validateToken();
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
    _sessionState.startEditSession(node, enabledProfiles);
  }

  void updateSession({
    double? directionDeg,
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
    LatLng? target,
  }) {
    _sessionState.updateSession(
      directionDeg: directionDeg,
      profile: profile,
      operatorProfile: operatorProfile,
      target: target,
    );
  }

  void updateEditSession({
    double? directionDeg,
    NodeProfile? profile,
    OperatorProfile? operatorProfile,
    LatLng? target,
  }) {
    _sessionState.updateEditSession(
      directionDeg: directionDeg,
      profile: profile,
      operatorProfile: operatorProfile,
      target: target,
    );
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

  // ---------- Navigation Methods ----------
  void enterSearchMode(LatLng mapCenter) {
    _navigationState.enterSearchMode(mapCenter);
  }

  void cancelSearchMode() {
    _navigationState.cancelSearchMode();
  }

  void updateProvisionalPinLocation(LatLng newLocation) {
    _navigationState.updateProvisionalPinLocation(newLocation);
  }

  void selectSearchResult(SearchResult result) {
    _navigationState.selectSearchResult(result);
  }

  void startRouteSetup({required bool settingStart}) {
    _navigationState.startRouteSetup(settingStart: settingStart);
  }

  void selectRouteLocation() {
    _navigationState.selectRouteLocation();
  }

  void startRoute() {
    _navigationState.startRoute();
  }

  void cancelRoute() {
    _navigationState.cancelRoute();
  }

  void viewRouteOverview() {
    _navigationState.viewRouteOverview();
  }

  void returnToActiveRoute() {
    _navigationState.returnToActiveRoute();
  }

  // Navigation search methods
  Future<void> searchNavigation(String query) async {
    await _navigationState.search(query);
  }

  void clearNavigationSearchResults() {
    _navigationState.clearSearchResults();
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

  set maxCameras(int n) {
    _settingsState.maxCameras = n;
  }

  Future<void> setUploadMode(UploadMode mode) async {
    // Clear node cache when switching upload modes to prevent mixing production/sandbox data
    NodeCache.instance.clear();
    CameraProviderWithCache.instance.notifyListeners();
    debugPrint('[AppState] Cleared node cache due to upload mode change');
    
    await _settingsState.setUploadMode(mode);
    await _authState.onUploadModeChanged(mode);
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
      uploadMode: uploadMode,
      getAccessToken: _authState.getAccessToken,
    );
  }

  @override
  void dispose() {
    _authState.removeListener(_onStateChanged);
    _navigationState.removeListener(_onStateChanged);
    _operatorProfileState.removeListener(_onStateChanged);
    _profileState.removeListener(_onStateChanged);
    _searchState.removeListener(_onStateChanged);
    _sessionState.removeListener(_onStateChanged);
    _settingsState.removeListener(_onStateChanged);
    _uploadQueueState.removeListener(_onStateChanged);
    
    _uploadQueueState.dispose();
    super.dispose();
  }
}

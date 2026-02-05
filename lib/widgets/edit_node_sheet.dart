import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../models/node_profile.dart';
import '../models/operator_profile.dart';
import '../models/pending_upload.dart';
import '../services/localization_service.dart';
import '../services/map_data_provider.dart';
import '../services/node_data_manager.dart';
import '../services/changelog_service.dart';
import '../state/settings_state.dart';
import '../state/session_state.dart';
import 'refine_tags_sheet.dart';
import 'advanced_edit_options_sheet.dart';
import 'proximity_warning_dialog.dart';
import 'submission_guide_dialog.dart';
import 'positioning_tutorial_overlay.dart';

class EditNodeSheet extends StatefulWidget {
  const EditNodeSheet({super.key, required this.session});

  final EditNodeSession session;

  @override
  State<EditNodeSheet> createState() => _EditNodeSheetState();
}

class _EditNodeSheetState extends State<EditNodeSheet> {
  bool _showTutorial = false;
  bool _isCheckingTutorial = true;

  @override
  void initState() {
    super.initState();
    _checkTutorialStatus();
    // Listen to node data manager for cache updates
    NodeDataManager().addListener(_onCacheUpdated);
  }

  void _onCacheUpdated() {
    // Rebuild when cache updates (e.g., when new data loads)
    if (mounted) setState(() {});
  }

  Future<void> _checkTutorialStatus() async {
    final hasCompleted = await ChangelogService().hasCompletedPositioningTutorial();
    if (mounted) {
      setState(() {
        _showTutorial = !hasCompleted;
        _isCheckingTutorial = false;
      });
      
      // If tutorial should be shown, register callback with AppState
      if (_showTutorial) {
        final appState = context.read<AppState>();
        appState.registerTutorialCallback(_hideTutorial);
      }
    }
  }

  void _hideTutorial() {
    if (mounted && _showTutorial) {
      setState(() {
        _showTutorial = false;
      });
    }
  }

  @override
  @override
  void dispose() {
    // Remove listener
    NodeDataManager().removeListener(_onCacheUpdated);
    
    // Clear tutorial callback when widget is disposed
    if (_showTutorial) {
      try {
        context.read<AppState>().clearTutorialCallback();
      } catch (e) {
        // Context might be unavailable during disposal, ignore
      }
    }
    super.dispose();
  }

  void _checkProximityAndCommit(BuildContext context, AppState appState, LocalizationService locService) {
    _checkSubmissionGuideAndProceed(context, appState, locService);
  }

  void _checkSubmissionGuideAndProceed(BuildContext context, AppState appState, LocalizationService locService) async {
    // Check if user has seen the submission guide
    final hasSeenGuide = await ChangelogService().hasSeenSubmissionGuide();
    
    if (!hasSeenGuide) {
      // Show submission guide dialog first
      final shouldProceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const SubmissionGuideDialog(),
      );
      
      // If user canceled the submission guide, don't proceed with submission
      if (shouldProceed != true) {
        return;
      }
    }
    
    // Now proceed with proximity check
    _checkProximityOnly(context, appState, locService);
  }

  void _checkProximityOnly(BuildContext context, AppState appState, LocalizationService locService) {
    // Check for nearby nodes within the configured distance, excluding the node being edited
    final nearbyNodes = MapDataProvider().findNodesWithinDistance(
      widget.session.target, 
      kNodeProximityWarningDistance,
      excludeNodeId: widget.session.originalNode.id,
    );
    
    if (nearbyNodes.isNotEmpty) {
      // Show proximity warning dialog
      showDialog<void>(
        context: context,
        builder: (context) => ProximityWarningDialog(
          nearbyNodes: nearbyNodes,
          distance: kNodeProximityWarningDistance,
          onGoBack: () {
            Navigator.of(context).pop(); // Close dialog
          },
          onSubmitAnyway: () {
            Navigator.of(context).pop(); // Close dialog
            _commitWithoutCheck(context, appState, locService);
          },
        ),
      );
    } else {
      // No nearby nodes, proceed with commit
      _commitWithoutCheck(context, appState, locService);
    }
  }

  void _commitWithoutCheck(BuildContext context, AppState appState, LocalizationService locService) {
    appState.commitEditSession();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(locService.t('node.editQueuedForUpload'))),
    );
  }

  /// Check if the edit session has any actual changes compared to the original node
  bool _hasActualChanges(EditNodeSession session) {
    debugPrint('EditNodeSheet: Checking for actual changes...');
    
    // Extract operation is always a change
    if (session.extractFromWay) {
      debugPrint('EditNodeSheet: Extract operation detected - changes found');
      return true;
    }
    
    // Check location change
    const double tolerance = 0.0000001; // ~1cm precision
    if ((session.target.latitude - session.originalNode.coord.latitude).abs() > tolerance ||
        (session.target.longitude - session.originalNode.coord.longitude).abs() > tolerance) {
      debugPrint('EditNodeSheet: Location change detected - changes found');
      return true;
    }
    
    // Check direction changes
    if (!_directionsEqual(session.directions, session.originalNode.directionDeg)) {
      debugPrint('EditNodeSheet: Direction change detected - changes found');
      return true;
    }
    
    // Check tag changes (including operator profile)
    final originalTags = session.originalNode.tags;
    final newTags = _getSessionCombinedTags(session);
    debugPrint('EditNodeSheet: Original tags: $originalTags');
    debugPrint('EditNodeSheet: New combined tags: $newTags');
    
    if (!_tagsEqual(originalTags, newTags)) {
      debugPrint('EditNodeSheet: Tag changes detected - changes found');
      return true;
    }
    
    debugPrint('EditNodeSheet: No changes detected');
    return false;
  }

  /// Compare two direction lists, handling empty vs [0] cases
  bool _directionsEqual(List<double> sessionDirs, List<double> originalDirs) {
    // Sort both lists for comparison
    final sorted1 = List<double>.from(sessionDirs)..sort();
    final sorted2 = List<double>.from(originalDirs)..sort();
    
    // Handle empty list cases
    if (sorted1.isEmpty && sorted2.isEmpty) return true;
    if (sorted1.isEmpty || sorted2.isEmpty) {
      // Special case: if one is empty and the other is [0], consider them different
      // because the user either added or removed a direction
      return false;
    }
    
    if (sorted1.length != sorted2.length) return false;
    
    for (int i = 0; i < sorted1.length; i++) {
      if ((sorted1[i] - sorted2[i]).abs() > 0.1) return false; // 0.1° tolerance
    }
    
    return true;
  }

  /// Compare two tag maps, ignoring direction tags (handled separately)
  bool _tagsEqual(Map<String, String> tags1, Map<String, String> tags2) {
    final filtered1 = Map<String, String>.from(tags1);
    final filtered2 = Map<String, String>.from(tags2);
    
    // Remove direction tags - they're handled separately
    filtered1.remove('direction');
    filtered1.remove('camera:direction');
    filtered2.remove('direction');
    filtered2.remove('camera:direction');
    
    return _mapEquals(filtered1, filtered2);
  }

  /// Deep equality check for maps
  bool _mapEquals(Map<String, String> map1, Map<String, String> map2) {
    if (map1.length != map2.length) return false;
    
    for (final entry in map1.entries) {
      if (map2[entry.key] != entry.value) return false;
    }
    
    return true;
  }

  /// Get the combined tags that would be submitted for this session
  Map<String, String> _getSessionCombinedTags(EditNodeSession session) {
    if (session.profile == null) return <String, String>{};
    
    // Create a temporary PendingUpload to use its getCombinedTags logic
    final tempUpload = PendingUpload(
      coord: session.target,
      direction: session.directions.isNotEmpty ? session.directions.first : 0.0,
      profile: session.profile,
      operatorProfile: session.operatorProfile,
      refinedTags: session.refinedTags,
      additionalExistingTags: session.additionalExistingTags, // Include additional existing tags!
      changesetComment: session.changesetComment, // Required parameter
      uploadMode: UploadMode.production, // Mode doesn't matter for tag combination
      operation: UploadOperation.modify,
      originalNodeId: session.originalNode.id, // Required for modify operations
    );
    
    return tempUpload.getCombinedTags();
  }

  /// Show dialog explaining why submission is disabled due to no changes
  void _showNoChangesDialog(BuildContext context, LocalizationService locService) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locService.t('editNode.noChangesTitle')),
        content: Text(locService.t('editNode.noChangesMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(locService.ok),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionControls(BuildContext context, AppState appState, EditNodeSession session, LocalizationService locService) {
    final requiresDirection = session.profile != null && session.profile!.requiresDirection;
    final is360Fov = session.profile?.fov == 360;
    final hasDirections = session.directions.isNotEmpty;
    final enableDirectionControls = requiresDirection && !is360Fov && hasDirections;
    final enableAddButton = requiresDirection && !is360Fov;
    
    // Force direction to 0 when FOV is 360 (omnidirectional)
    if (is360Fov && session.directionDegrees != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.updateEditSession(directionDeg: 0);
      });
    }
    
    // Format direction display text with bold for current direction
    String directionsText = '';
    if (requiresDirection && hasDirections) {
      final directionsWithBold = <String>[];
      for (int i = 0; i < session.directions.length; i++) {
        final dirStr = session.directions[i].round().toString();
        if (i == session.currentDirectionIndex) {
          directionsWithBold.add('**$dirStr**'); // Mark for bold formatting
        } else {
          directionsWithBold.add(dirStr);
        }
      }
      directionsText = directionsWithBold.join(', ');
    }

    return Column(
      children: [
        ListTile(
          title: requiresDirection 
            ? RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.titleMedium,
                  children: [
                    const TextSpan(text: 'Directions: '),
                    if (directionsText.isNotEmpty)
                      ...directionsText.split('**').asMap().entries.map((entry) {
                        final isEven = entry.key % 2 == 0;
                        return TextSpan(
                          text: entry.value,
                          style: TextStyle(
                            fontWeight: isEven ? FontWeight.normal : FontWeight.bold,
                          ),
                        );
                      })
                    else
                      const TextSpan(
                        text: 'None',
                        style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
                      ),
                  ],
                ),
              )
            : Text(locService.t('editNode.direction', params: [session.directionDegrees.round().toString()])),
          subtitle: Row(
            children: [
              // Slider takes most of the space
              Expanded(
                child: Slider(
                  min: 0,
                  max: 359,
                  divisions: 359,
                  value: session.directionDegrees,
                  label: session.directionDegrees.round().toString(),
                  onChanged: enableDirectionControls ? (v) => appState.updateEditSession(directionDeg: v) : null,
                ),
              ),
              // Direction control buttons - always show but grey out when direction not required
              const SizedBox(width: 8),
              // Remove button
              IconButton(
                icon: Icon(
                  Icons.remove, 
                  size: 20,
                  color: enableDirectionControls && appState.canRemoveDirection ? null : Theme.of(context).disabledColor,
                ),
                onPressed: enableDirectionControls && appState.canRemoveDirection
                    ? () => appState.removeDirection() 
                    : null,
                tooltip: requiresDirection 
                    ? (hasDirections 
                        ? (appState.canRemoveDirection ? 'Remove current direction' : 'Cannot remove - minimum reached')
                        : 'No directions to remove')
                    : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: kDirectionButtonMinWidth, minHeight: kDirectionButtonMinHeight),
              ),
              // Add button
              IconButton(
                icon: Icon(
                  Icons.add, 
                  size: 20,
                  color: enableAddButton && session.directions.length < 8 ? null : Theme.of(context).disabledColor,
                ),
                onPressed: enableAddButton && session.directions.length < 8 ? () => appState.addDirection() : null,
                tooltip: requiresDirection 
                    ? (session.directions.length >= 8 ? 'Maximum 8 directions allowed' : 'Add new direction') 
                    : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: kDirectionButtonMinWidth, minHeight: kDirectionButtonMinHeight),
              ),
              // Cycle button
              IconButton(
                icon: Icon(
                  Icons.repeat, 
                  size: 20,
                  color: enableDirectionControls && session.directions.length > 1 ? null : Theme.of(context).disabledColor,
                ),
                onPressed: enableDirectionControls && session.directions.length > 1 
                    ? () => appState.cycleDirection() 
                    : null,
                tooltip: requiresDirection 
                    ? (hasDirections 
                        ? (session.directions.length > 1 ? 'Cycle through directions' : 'Only one direction')
                        : 'No directions to cycle') 
                    : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: kDirectionButtonMinWidth, minHeight: kDirectionButtonMinHeight),
              ),
            ],
          ),
        ),
        // Show info text when profile doesn't require direction or when no directions exist
        if (!requiresDirection)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This profile does not require a direction.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else if (requiresDirection && !hasDirections)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'This device currently has no direction. Tap the + button to add one.',
                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();

        void _commit() {
          // Check if there are any actual changes to submit
          if (!_hasActualChanges(widget.session)) {
            _showNoChangesDialog(context, locService);
            return;
          }
          
          _checkProximityAndCommit(context, appState, locService);
        }

        void _cancel() {
          appState.cancelEditSession();
          Navigator.pop(context);
        }

        final session = widget.session;
        final submittableProfiles = appState.enabledProfiles.where((p) => p.isSubmittable).toList();
        final isSandboxMode = appState.uploadMode == UploadMode.sandbox;
        
        // Check if we have good cache coverage around the node position
        bool hasGoodCoverage = true;
        final nodeCoord = session.originalNode.coord;
        const double bufferDegrees = 0.001; // ~100m buffer
        final targetBounds = LatLngBounds(
          LatLng(nodeCoord.latitude - bufferDegrees, nodeCoord.longitude - bufferDegrees),
          LatLng(nodeCoord.latitude + bufferDegrees, nodeCoord.longitude + bufferDegrees),
        );
        hasGoodCoverage = MapDataProvider().hasGoodCoverageFor(targetBounds);
        
        // If strict coverage check fails, fall back to checking if we have any nodes nearby
        // This handles the timing issue where cache might not be marked as "covered" yet
        if (!hasGoodCoverage) {
          final nearbyNodes = MapDataProvider().findNodesWithinDistance(
            nodeCoord, 
            200.0, // 200m radius - if we have nodes nearby, we likely have good data
          );
          hasGoodCoverage = nearbyNodes.isNotEmpty;
        }
        
        final allowSubmit = kEnableNodeEdits && 
            appState.isLoggedIn && 
            submittableProfiles.isNotEmpty && 
            session.profile != null && 
            session.profile!.isSubmittable &&
            hasGoodCoverage;
        
        void _navigateToLogin() {
          Navigator.pushNamed(context, '/settings/osm-account');
        }
        
        void _openRefineTags() async {
          final result = await Navigator.push<RefineTagsResult?>(
            context,
            MaterialPageRoute(
              builder: (context) => RefineTagsSheet(
                selectedOperatorProfile: session.operatorProfile,
                selectedProfile: session.profile,
                currentRefinedTags: session.refinedTags,
                currentAdditionalExistingTags: session.additionalExistingTags,
                originalNodeTags: session.originalNode.tags,
                operation: session.extractFromWay ? UploadOperation.extract : UploadOperation.modify,
              ),
              fullscreenDialog: true,
            ),
          );
          if (result != null) {
            debugPrint('EditNodeSheet: Updating session from refine tags result');
            debugPrint('EditNodeSheet: Profile: ${session.profile?.name}');
            debugPrint('EditNodeSheet: AdditionalExistingTags: ${result.additionalExistingTags}');
            debugPrint('EditNodeSheet: Current session additionalExistingTags: ${session.additionalExistingTags}');
            
            appState.updateEditSession(
              operatorProfile: result.operatorProfile,
              refinedTags: result.refinedTags,
              additionalExistingTags: result.additionalExistingTags,
              changesetComment: result.changesetComment,
            );
          }
        }

        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.loose,
          children: [
            Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                locService.t('editNode.title', params: [session.originalNode.id.toString()]),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text(locService.t('editNode.profile')),
                trailing: _buildProfileDropdown(context, appState, session, submittableProfiles, locService),
              ),
              // Direction controls
              _buildDirectionControls(context, appState, session, locService),

              // Constraint message for nodes that cannot be moved
              if (session.originalNode.isConstrained)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      // Extract from way checkbox (only show if enabled in dev config)
                      if (kEnableNodeExtraction) ...[
                        CheckboxListTile(
                          title: Text(locService.t('editNode.extractFromWay')),
                          subtitle: Text(locService.t('editNode.extractFromWaySubtitle')),
                          value: session.extractFromWay,
                          onChanged: (value) {
                            appState.updateEditSession(extractFromWay: value);
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Constraint info message (only show if extract is not checked or not enabled)
                      if (!kEnableNodeExtraction || !session.extractFromWay) ...[
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                locService.t('editNode.cannotMoveConstrainedNode'),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _openAdvancedEdit(context),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(locService.t('actions.useAdvancedEditor')),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 32),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              if (!kEnableNodeEdits)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.construction, color: Colors.orange, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locService.t('editNode.temporarilyDisabled'),
                          style: const TextStyle(color: Colors.orange, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!appState.isLoggedIn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locService.t('editNode.mustBeLoggedIn'),
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (submittableProfiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locService.t('editNode.enableSubmittableProfile'),
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (session.profile == null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locService.t('editNode.profileRequired'),
                          style: const TextStyle(color: Colors.orange, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!session.profile!.isSubmittable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locService.t('editNode.profileViewOnlyWarning'),
                          style: const TextStyle(color: Colors.orange, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!hasGoodCoverage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_download, color: Colors.blue, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locService.t('editNode.loadingAreaData'),
                          style: const TextStyle(color: Colors.blue, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: session.profile != null ? _openRefineTags : null, // Disabled when no profile selected
                    icon: const Icon(Icons.tune),
                    label: Text(locService.t('editNode.refineTags')),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _cancel,
                        child: Text(locService.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: !appState.isLoggedIn ? _navigateToLogin : (allowSubmit ? _commit : null),
                        child: Text(!appState.isLoggedIn ? locService.t('actions.logIn') : locService.t('actions.saveEdit')),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            ),

            // Tutorial overlay - show only if tutorial should be shown and we're done checking
            if (!_isCheckingTutorial && _showTutorial)
              Positioned.fill(
                child: PositioningTutorialOverlay(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildProfileDropdown(BuildContext context, AppState appState, EditNodeSession session, List<NodeProfile> submittableProfiles, LocalizationService locService) {
    // Display name for the current profile - localize the existing tags profile
    String getDisplayName(NodeProfile? profile) {
      if (profile == null) return locService.t('editNode.selectProfile');
      if (profile.id.startsWith('temp-empty-')) {
        return locService.t('editNode.existingTags');
      }
      return profile.name;
    }
    
    return PopupMenuButton<String>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              getDisplayName(session.profile),
              style: TextStyle(
                fontSize: 16,
                color: session.profile != null ? null : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
      itemBuilder: (context) => [
        // Existing tags profile (always first in edit mode)
        PopupMenuItem<String>(
          value: 'existing_tags',
          child: Text(locService.t('editNode.existingTags')),
        ),
        // Divider after existing tags profile
        if (submittableProfiles.isNotEmpty) 
          const PopupMenuDivider(),
        // Regular profiles
        ...submittableProfiles.map(
          (profile) => PopupMenuItem<String>(
            value: 'profile_${profile.id}',
            child: Text(profile.name),
          ),
        ),
        // Divider
        if (submittableProfiles.isNotEmpty) const PopupMenuDivider(),
        // Get more... option
        PopupMenuItem<String>(
          value: 'get_more',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 16),
              const SizedBox(width: 8),
              Text(
                locService.t('profiles.getMore'),
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'get_more') {
          _openIdentifyWebsite(context);
        } else if (value == 'existing_tags') {
          // Re-create and select the existing tags profile
          final existingTagsProfile = NodeProfile.createExistingTagsProfile(session.originalNode);
          appState.updateEditSession(profile: existingTagsProfile);
        } else if (value.startsWith('profile_')) {
          final profileId = value.substring(8); // Remove 'profile_' prefix
          final profile = submittableProfiles.firstWhere((p) => p.id == profileId);
          appState.updateEditSession(profile: profile);
        }
      },
    );
  }

  void _openIdentifyWebsite(BuildContext context) async {
    const url = 'https://deflock.me/identify';
    
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // Force external browser
        );
      } else {
        if (context.mounted) {
          _showErrorSnackBar(context, 'Unable to open website');
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackBar(context, 'Error opening website: $e');
      }
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _openAdvancedEdit(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AdvancedEditOptionsSheet(node: widget.session.originalNode),
    );
  }
}
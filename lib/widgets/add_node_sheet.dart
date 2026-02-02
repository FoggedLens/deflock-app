import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../models/node_profile.dart';
import '../models/operator_profile.dart';
import '../services/localization_service.dart';
import '../services/map_data_provider.dart';
import '../services/node_data_manager.dart';
import '../services/changelog_service.dart';
import 'refine_tags_sheet.dart';
import 'proximity_warning_dialog.dart';
import 'submission_guide_dialog.dart';
import 'positioning_tutorial_overlay.dart';

class AddNodeSheet extends StatefulWidget {
  const AddNodeSheet({super.key, required this.session});

  final AddNodeSession session;

  @override
  State<AddNodeSheet> createState() => _AddNodeSheetState();
}

class _AddNodeSheetState extends State<AddNodeSheet> {
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

  /// Listen for tutorial completion from AppState
  void _onTutorialCompleted() {
    _hideTutorial();
  }

  /// Also check periodically if tutorial was completed by another sheet
  void _recheckTutorialStatus() async {
    if (_showTutorial) {
      final hasCompleted = await ChangelogService().hasCompletedPositioningTutorial();
      if (hasCompleted && mounted) {
        setState(() {
          _showTutorial = false;
        });
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
    // Only check proximity if we have a target location
    if (widget.session.target == null) {
      _commitWithoutCheck(context, appState, locService);
      return;
    }
    
    // Check for nearby nodes within the configured distance
    final nearbyNodes = MapDataProvider().findNodesWithinDistance(
      widget.session.target!, 
      kNodeProximityWarningDistance,
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
    appState.commitSession();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(locService.t('node.queuedForUpload'))),
    );
  }

  Widget _buildProfileDropdown(BuildContext context, AppState appState, AddNodeSession session, List<NodeProfile> submittableProfiles, LocalizationService locService) {
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
              session.profile?.name ?? locService.t('addNode.selectProfile'),
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
        } else if (value.startsWith('profile_')) {
          final profileId = value.substring(8); // Remove 'profile_' prefix
          final profile = submittableProfiles.firstWhere((p) => p.id == profileId);
          appState.updateSession(profile: profile);
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

  Widget _buildDirectionControls(BuildContext context, AppState appState, AddNodeSession session, LocalizationService locService) {
    final requiresDirection = session.profile != null && session.profile!.requiresDirection;
    final is360Fov = session.profile?.fov == 360;
    final enableDirectionControls = requiresDirection && !is360Fov;
    
    // Force direction to 0 when FOV is 360 (omnidirectional)
    if (is360Fov && session.directionDegrees != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.updateSession(directionDeg: 0);
      });
    }
    
    // Format direction display text with bold for current direction
    String directionsText = '';
    if (requiresDirection) {
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
                      }),
                  ],
                ),
              )
            : Text(locService.t('addNode.direction', params: [session.directionDegrees.round().toString()])),
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
                  onChanged: enableDirectionControls ? (v) => appState.updateSession(directionDeg: v) : null,
                ),
              ),
              // Direction control buttons - always show but grey out when direction not required
              const SizedBox(width: 8),
              // Remove button
              IconButton(
                icon: Icon(
                  Icons.remove, 
                  size: 20,
                  color: enableDirectionControls ? null : Theme.of(context).disabledColor,
                ),
                onPressed: enableDirectionControls && session.directions.length > 1 
                    ? () => appState.removeDirection() 
                    : null,
                tooltip: requiresDirection ? 'Remove current direction' : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: kDirectionButtonMinWidth, minHeight: kDirectionButtonMinHeight),
              ),
              // Add button
              IconButton(
                icon: Icon(
                  Icons.add, 
                  size: 20,
                  color: enableDirectionControls && session.directions.length < 8 ? null : Theme.of(context).disabledColor,
                ),
                onPressed: enableDirectionControls && session.directions.length < 8 ? () => appState.addDirection() : null,
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
                  color: enableDirectionControls ? null : Theme.of(context).disabledColor,
                ),
                onPressed: enableDirectionControls && session.directions.length > 1 
                    ? () => appState.cycleDirection() 
                    : null,
                tooltip: requiresDirection ? 'Cycle through directions' : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: kDirectionButtonMinWidth, minHeight: kDirectionButtonMinHeight),
              ),
            ],
          ),
        ),
        // Show info text when profile doesn't require direction
        if (!requiresDirection)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.grey, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locService.t('addNode.profileNoDirectionInfo'),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
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
          _checkProximityAndCommit(context, appState, locService);
        }

        void _cancel() {
          appState.cancelSession();
          Navigator.pop(context);
        }

        final session = widget.session;
        final submittableProfiles = appState.enabledProfiles.where((p) => p.isSubmittable).toList();
        
        // Check if we have good cache coverage around the node position
        bool hasGoodCoverage = true;
        if (session.target != null) {
          // Create a small bounds around the target position to check coverage
          const double bufferDegrees = 0.001; // ~100m buffer
          final targetBounds = LatLngBounds(
            LatLng(session.target!.latitude - bufferDegrees, session.target!.longitude - bufferDegrees),
            LatLng(session.target!.latitude + bufferDegrees, session.target!.longitude + bufferDegrees),
          );
          hasGoodCoverage = MapDataProvider().hasGoodCoverageFor(targetBounds);
          
          // If strict coverage check fails, fall back to checking if we have any nodes nearby
          // This handles the timing issue where cache might not be marked as "covered" yet
          if (!hasGoodCoverage) {
            final nearbyNodes = MapDataProvider().findNodesWithinDistance(
              session.target!, 
              200.0, // 200m radius - if we have nodes nearby, we likely have good data
            );
            hasGoodCoverage = nearbyNodes.isNotEmpty;
          }
        }
        
        final allowSubmit = appState.isLoggedIn && 
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
                operation: UploadOperation.create,
              ),
              fullscreenDialog: true,
            ),
          );
          if (result != null) {
            appState.updateSession(
              operatorProfile: result.operatorProfile,
              refinedTags: result.refinedTags,
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
              const SizedBox(height: 16),
              ListTile(
                title: Text(locService.t('addNode.profile')),
                trailing: _buildProfileDropdown(context, appState, session, submittableProfiles, locService),
              ),
              // Direction controls
              _buildDirectionControls(context, appState, session, locService),

              if (!appState.isLoggedIn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          locService.t('addNode.mustBeLoggedIn'),
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
                          locService.t('addNode.enableSubmittableProfile'),
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
                          locService.t('addNode.profileRequired'),
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
                          locService.t('addNode.profileViewOnlyWarning'),
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
                          locService.t('addNode.loadingAreaData'),
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
                    label: Text(locService.t('addNode.refineTags')),
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
                        child: Text(!appState.isLoggedIn ? locService.t('actions.logIn') : locService.t('actions.submit')),
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
}


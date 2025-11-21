import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../dev_config.dart';
import '../models/node_profile.dart';
import '../models/operator_profile.dart';
import '../services/localization_service.dart';
import 'refine_tags_sheet.dart';

class AddNodeSheet extends StatelessWidget {
  const AddNodeSheet({super.key, required this.session});

  final AddNodeSession session;

  Widget _buildDirectionControls(BuildContext context, AppState appState, AddNodeSession session, LocalizationService locService) {
    final requiresDirection = session.profile != null && session.profile!.requiresDirection;
    
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
                  onChanged: requiresDirection ? (v) => appState.updateSession(directionDeg: v) : null,
                ),
              ),
              // Direction control buttons - always show but grey out when direction not required
              const SizedBox(width: 8),
              // Remove button
              IconButton(
                icon: Icon(
                  Icons.remove, 
                  size: 20,
                  color: requiresDirection ? null : Theme.of(context).disabledColor,
                ),
                onPressed: requiresDirection && session.directions.length > 1 
                    ? () => appState.removeDirection() 
                    : null,
                tooltip: requiresDirection ? 'Remove current direction' : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: dev.kDirectionButtonMinWidth, minHeight: dev.kDirectionButtonMinHeight),
              ),
              // Add button
              IconButton(
                icon: Icon(
                  Icons.add, 
                  size: 20,
                  color: requiresDirection && session.directions.length < 8 ? null : Theme.of(context).disabledColor,
                ),
                onPressed: requiresDirection && session.directions.length < 8 ? () => appState.addDirection() : null,
                tooltip: requiresDirection 
                    ? (session.directions.length >= 8 ? 'Maximum 8 directions allowed' : 'Add new direction') 
                    : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: dev.kDirectionButtonMinWidth, minHeight: dev.kDirectionButtonMinHeight),
              ),
              // Cycle button
              IconButton(
                icon: Icon(
                  Icons.repeat, 
                  size: 20,
                  color: requiresDirection ? null : Theme.of(context).disabledColor,
                ),
                onPressed: requiresDirection && session.directions.length > 1 
                    ? () => appState.cycleDirection() 
                    : null,
                tooltip: requiresDirection ? 'Cycle through directions' : 'Direction not required for this profile',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: dev.kDirectionButtonMinWidth, minHeight: dev.kDirectionButtonMinHeight),
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
          appState.commitSession();
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locService.t('node.queuedForUpload'))),
          );
        }

        void _cancel() {
          appState.cancelSession();
          Navigator.pop(context);
        }

        final submittableProfiles = appState.enabledProfiles.where((p) => p.isSubmittable).toList();
        final allowSubmit = appState.isLoggedIn && 
            submittableProfiles.isNotEmpty && 
            session.profile != null && 
            session.profile!.isSubmittable;
        
        void _openRefineTags() async {
          final result = await Navigator.push<OperatorProfile?>(
            context,
            MaterialPageRoute(
              builder: (context) => RefineTagsSheet(
                selectedOperatorProfile: session.operatorProfile,
              ),
              fullscreenDialog: true,
            ),
          );
          if (result != session.operatorProfile) {
            appState.updateSession(operatorProfile: result);
          }
        }

        return Column(
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
                trailing: DropdownButton<NodeProfile?>(
                  value: session.profile,
                  hint: Text(locService.t('addNode.selectProfile')),
                  items: submittableProfiles
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                      .toList(),
                  onChanged: (p) => appState.updateSession(profile: p),
                ),
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
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: session.profile != null ? _openRefineTags : null, // Disabled when no profile selected
                    icon: const Icon(Icons.tune),
                    label: Text(session.operatorProfile != null
                        ? locService.t('addNode.refineTagsWithProfile', params: [session.operatorProfile!.name])
                        : locService.t('addNode.refineTags')),
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
                        onPressed: allowSubmit ? _commit : null,
                        child: Text(locService.t('actions.submit')),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
        );
      },
    );
  }
}


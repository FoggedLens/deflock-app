import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/node_profile.dart';
import '../models/operator_profile.dart';
import '../services/localization_service.dart';
import 'refine_tags_sheet.dart';

class AddNodeSheet extends StatelessWidget {
  const AddNodeSheet({super.key, required this.session});

  final AddNodeSession session;

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
        final allowSubmit = appState.isLoggedIn && submittableProfiles.isNotEmpty && session.profile.isSubmittable;
        
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

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
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
                trailing: DropdownButton<NodeProfile>(
                  value: session.profile,
                  items: submittableProfiles
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                      .toList(),
                  onChanged: (p) =>
                      appState.updateSession(profile: p ?? session.profile),
                ),
              ),
              ListTile(
                title: Text(locService.t('addNode.direction', params: [session.directionDegrees.round().toString()])),
                subtitle: Slider(
                  min: 0,
                  max: 359,
                  divisions: 359,
                  value: session.directionDegrees,
                  label: session.directionDegrees.round().toString(),
                  onChanged: session.profile.requiresDirection 
                      ? (v) => appState.updateSession(directionDeg: v)
                      : null, // Disables slider when requiresDirection is false
                ),
              ),
              if (!session.profile.requiresDirection)
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
              else if (!session.profile.isSubmittable)
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
                    onPressed: _openRefineTags,
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
          ),
        );
      },
    );
  }
}


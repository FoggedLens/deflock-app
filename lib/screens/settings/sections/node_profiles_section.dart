import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../models/node_profile.dart';
import '../../../services/localization_service.dart';
import '../../../widgets/profile_add_choice_dialog.dart';
import '../../profile_editor.dart';

class NodeProfilesSection extends StatelessWidget {
  const NodeProfilesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  locService.t('profiles.nodeProfiles'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () => _showAddProfileDialog(context),
                  icon: const Icon(Icons.add),
                  label: Text(locService.t('profiles.newProfile')),
                ),
              ],
            ),
            ...appState.profiles.map(
              (p) => ListTile(
                leading: Checkbox(
                  value: appState.isEnabled(p),
                  onChanged: (v) => appState.toggleProfile(p, v ?? false),
                ),
                title: Text(p.name),
                subtitle: Text(p.builtin ? locService.t('profiles.builtIn') : locService.t('profiles.custom')),
                trailing: !p.editable 
                  ? PopupMenuButton(
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'view',
                          child: Row(
                            children: [
                              const Icon(Icons.visibility),
                              const SizedBox(width: 8),
                              Text(locService.t('profiles.view')),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'view') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileEditor(profile: p),
                            ),
                          );
                        }
                      },
                    )
                  : PopupMenuButton(
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(Icons.edit),
                              const SizedBox(width: 8),
                            Text(locService.t('actions.edit')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(Icons.delete, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(locService.t('profiles.deleteProfile'), style: const TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileEditor(profile: p),
                            ),
                          );
                        } else if (value == 'delete') {
                          _showDeleteProfileDialog(context, p);
                        }
                      },
                    ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddProfileDialog(BuildContext context) async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => const ProfileAddChoiceDialog(),
    );
    
    // If user chose to create custom profile, open the profile editor
    if (result == 'create') {
      _createNewProfile(context);
    }
    // If user chose import from website, ProfileAddChoiceDialog handles opening the URL
  }

  void _createNewProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileEditor(
          profile: NodeProfile(
            id: const Uuid().v4(),
            name: '',
            tags: const {},
          ),
        ),
      ),
    );
  }

void _showDeleteProfileDialog(BuildContext context, NodeProfile profile) {
  final locService = LocalizationService.instance;
  final appState = context.read<AppState>();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(locService.t('profiles.deleteProfile')),
      content: Text(locService.t('profiles.deleteProfileConfirm', params: [profile.name])),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(locService.t('actions.cancel')),
        ),
        TextButton(
          onPressed: () {
            appState.deleteProfile(profile);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(locService.t('profiles.profileDeleted'))),
            );
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(locService.t('profiles.deleteProfile')),
        ),
      ],
    ),
  );
}
}

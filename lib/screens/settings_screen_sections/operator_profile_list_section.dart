import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/operator_profile.dart';
import '../../services/localization_service.dart';
import '../operator_profile_editor.dart';

class OperatorProfileListSection extends StatelessWidget {
  const OperatorProfileListSection({super.key});

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
                Text(locService.t('operatorProfiles.title'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OperatorProfileEditor(
                        profile: OperatorProfile(
                          id: const Uuid().v4(),
                          name: '',
                          tags: const {},
                        ),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(locService.t('profiles.newProfile')),
                ),
              ],
            ),
            if (appState.operatorProfiles.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  locService.t('operatorProfiles.noProfilesMessage'),
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...appState.operatorProfiles.map(
                (p) => ListTile(
                  title: Text(p.name),
                  subtitle: Text(locService.t('operatorProfiles.tagsCount', params: [p.tags.length.toString()])),
                  trailing: PopupMenuButton(
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
                            Text(locService.t('operatorProfiles.deleteOperatorProfile'), style: const TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OperatorProfileEditor(profile: p),
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

void _showDeleteProfileDialog(BuildContext context, OperatorProfile profile) {
  final locService = LocalizationService.instance;
  final appState = context.read<AppState>();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(locService.t('operatorProfiles.deleteOperatorProfile')),
      content: Text(locService.t('operatorProfiles.deleteOperatorProfileConfirm', params: [profile.name])),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(locService.t('actions.cancel')),
        ),
        TextButton(
          onPressed: () {
            appState.deleteOperatorProfile(profile);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(locService.t('operatorProfiles.operatorProfileDeleted'))),
            );
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(locService.t('operatorProfiles.deleteOperatorProfile')),
        ),
      ],
    ),
  );
}
}
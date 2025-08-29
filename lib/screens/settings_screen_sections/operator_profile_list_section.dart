import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/operator_profile.dart';
import '../operator_profile_editor.dart';

class OperatorProfileListSection extends StatelessWidget {
  const OperatorProfileListSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Operator Profiles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
              label: const Text('New Profile'),
            ),
          ],
        ),
        if (appState.operatorProfiles.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'No operator profiles defined. Create one to apply operator tags to camera submissions.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...appState.operatorProfiles.map(
            (p) => ListTile(
              title: Text(p.name),
              subtitle: Text('${p.tags.length} tags'),
              trailing: PopupMenuButton(
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: const Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: const Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
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
  }

void _showDeleteProfileDialog(BuildContext context, OperatorProfile profile) {
  final appState = context.read<AppState>();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Operator Profile'),
      content: Text('Are you sure you want to delete "${profile.name}"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            appState.deleteOperatorProfile(profile);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Operator profile deleted')),
            );
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}
}
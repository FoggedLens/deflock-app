import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/camera_profile.dart';
import '../profile_editor.dart';

class ProfileListSection extends StatelessWidget {
  const ProfileListSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Camera Profiles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileEditor(
                    profile: CameraProfile(
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
        ...appState.profiles.map(
          (p) => ListTile(
            leading: Checkbox(
              value: appState.isEnabled(p),
              onChanged: (v) => appState.toggleProfile(p, v ?? false),
            ),
            title: Text(p.name),
            subtitle: Text(p.builtin ? 'Built-in' : 'Custom'),
            trailing: !p.editable 
              ? PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'view',
                      child: const Row(
                        children: [
                          Icon(Icons.visibility),
                          SizedBox(width: 8),
                          Text('View'),
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
  }

void _showDeleteProfileDialog(BuildContext context, CameraProfile profile) {
  final appState = context.read<AppState>();
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Profile'),
      content: Text('Are you sure you want to delete "${profile.name}"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            appState.deleteProfile(profile);
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile deleted')),
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

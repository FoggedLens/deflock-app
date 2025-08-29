import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/camera_profile.dart';
import '../app_state.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.profile});

  final CameraProfile profile;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late TextEditingController _nameCtrl;
  late List<MapEntry<String, String>> _tags;
  late bool _requiresDirection;

  static const _defaultTags = [
    MapEntry('man_made', 'surveillance'),
    MapEntry('surveillance', 'public'),
    MapEntry('surveillance:zone', 'traffic'),
    MapEntry('surveillance:type', 'ALPR'),
    MapEntry('camera:type', 'fixed'),
    MapEntry('camera:mount', ''),
    MapEntry('manufacturer', ''),
    MapEntry('manufacturer:wikidata', ''),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.name);
    _requiresDirection = widget.profile.requiresDirection;

    if (widget.profile.tags.isEmpty) {
      // New profile → start with sensible defaults
      _tags = [..._defaultTags];
    } else {
      _tags = widget.profile.tags.entries.toList();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile.builtin 
            ? 'View Profile' 
            : (widget.profile.name.isEmpty ? 'New Profile' : 'Edit Profile')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            readOnly: widget.profile.builtin,
            decoration: const InputDecoration(
              labelText: 'Profile name',
              hintText: 'e.g., Custom ALPR Camera',
            ),
          ),
          const SizedBox(height: 16),
          if (!widget.profile.builtin)
            CheckboxListTile(
              title: const Text('Requires Direction'),
              subtitle: const Text('Whether cameras of this type need a direction tag'),
              value: _requiresDirection,
              onChanged: (value) => setState(() => _requiresDirection = value ?? true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('OSM Tags',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (!widget.profile.builtin)
                TextButton.icon(
                  onPressed: () => setState(() => _tags.add(const MapEntry('', ''))),
                  icon: const Icon(Icons.add),
                  label: const Text('Add tag'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ..._buildTagRows(),
          const SizedBox(height: 24),
          if (!widget.profile.builtin)
            ElevatedButton(
              onPressed: _save,
              child: const Text('Save Profile'),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildTagRows() {
    return List.generate(_tags.length, (i) {
      final keyController = TextEditingController(text: _tags[i].key);
      final valueController = TextEditingController(text: _tags[i].value);
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'key',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                controller: keyController,
                readOnly: widget.profile.builtin,
                onChanged: widget.profile.builtin 
                    ? null 
                    : (v) => _tags[i] = MapEntry(v, _tags[i].value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'value',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                controller: valueController,
                readOnly: widget.profile.builtin,
                onChanged: widget.profile.builtin 
                    ? null 
                    : (v) => _tags[i] = MapEntry(_tags[i].key, v),
              ),
            ),
            if (!widget.profile.builtin)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => setState(() => _tags.removeAt(i)),
              ),
          ],
        ),
      );
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Profile name is required')));
      return;
    }
    
    final tagMap = <String, String>{};
    for (final e in _tags) {
      if (e.key.trim().isEmpty || e.value.trim().isEmpty) continue;
      tagMap[e.key.trim()] = e.value.trim();
    }
    
    if (tagMap.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('At least one tag is required')));
      return;
    }

    final newProfile = widget.profile.copyWith(
      id: widget.profile.id.isEmpty ? const Uuid().v4() : widget.profile.id,
      name: name,
      tags: tagMap,
      builtin: false,
      requiresDirection: _requiresDirection,
    );
    
    context.read<AppState>().addOrUpdateProfile(newProfile);
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Profile "${newProfile.name}" saved')),
    );
  }
}

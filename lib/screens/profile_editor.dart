import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/node_profile.dart';
import '../app_state.dart';
import '../services/localization_service.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.profile});

  final NodeProfile profile;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late TextEditingController _nameCtrl;
  late List<MapEntry<String, String>> _tags;
  late bool _requiresDirection;
  late bool _submittable;

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
    _submittable = widget.profile.submittable;

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
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return Scaffold(
          appBar: AppBar(
            title: Text(!widget.profile.editable 
                ? locService.t('profileEditor.viewProfile')
                : (widget.profile.name.isEmpty ? locService.t('profileEditor.newProfile') : locService.t('profileEditor.editProfile'))),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameCtrl,
                readOnly: !widget.profile.editable,
                decoration: InputDecoration(
                  labelText: locService.t('profileEditor.profileName'),
                  hintText: locService.t('profileEditor.profileNameHint'),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.profile.editable) ...[
                CheckboxListTile(
                  title: Text(locService.t('profileEditor.requiresDirection')),
                  subtitle: Text(locService.t('profileEditor.requiresDirectionSubtitle')),
                  value: _requiresDirection,
                  onChanged: (value) => setState(() => _requiresDirection = value ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: Text(locService.t('profileEditor.submittable')),
                  subtitle: Text(locService.t('profileEditor.submittableSubtitle')),
                  value: _submittable,
                  onChanged: (value) => setState(() => _submittable = value ?? true),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
              const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(locService.t('profileEditor.osmTags'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (widget.profile.editable)
                      TextButton.icon(
                        onPressed: () => setState(() => _tags.add(const MapEntry('', ''))),
                        icon: const Icon(Icons.add),
                        label: Text(locService.t('profileEditor.addTag')),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              ..._buildTagRows(),
              const SizedBox(height: 24),
              if (widget.profile.editable)
                ElevatedButton(
                  onPressed: _save,
                  child: Text(locService.t('profileEditor.saveProfile')),
                ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTagRows() {
    final locService = LocalizationService.instance;
    
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
                decoration: InputDecoration(
                  hintText: locService.t('profileEditor.keyHint'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                controller: keyController,
                readOnly: !widget.profile.editable,
                onChanged: !widget.profile.editable 
                    ? null 
                    : (v) => _tags[i] = MapEntry(v, _tags[i].value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextField(
                decoration: InputDecoration(
                  hintText: locService.t('profileEditor.valueHint'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                controller: valueController,
                readOnly: !widget.profile.editable,
                onChanged: !widget.profile.editable 
                    ? null 
                    : (v) => _tags[i] = MapEntry(_tags[i].key, v),
              ),
            ),
            if (widget.profile.editable)
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
    final locService = LocalizationService.instance;
    final name = _nameCtrl.text.trim();
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(locService.t('profileEditor.profileNameRequired'))));
      return;
    }
    
    final tagMap = <String, String>{};
    for (final e in _tags) {
      if (e.key.trim().isEmpty || e.value.trim().isEmpty) continue;
      tagMap[e.key.trim()] = e.value.trim();
    }
    
    if (tagMap.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(locService.t('profileEditor.atLeastOneTagRequired'))));
      return;
    }

    final newProfile = widget.profile.copyWith(
      id: widget.profile.id.isEmpty ? const Uuid().v4() : widget.profile.id,
      name: name,
      tags: tagMap,
      builtin: false,
      requiresDirection: _requiresDirection,
      submittable: _submittable,
      editable: true, // All custom profiles are editable by definition
    );
    
    context.read<AppState>().addOrUpdateProfile(newProfile);
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(locService.t('profileEditor.profileSaved', params: [newProfile.name]))),
    );
  }
}

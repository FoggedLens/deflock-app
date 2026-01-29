import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/node_profile.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import '../widgets/nsi_tag_value_field.dart';

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
  late TextEditingController _fovCtrl;

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
    _fovCtrl = TextEditingController(text: widget.profile.fov?.toString() ?? '');

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
    _fovCtrl.dispose();
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
            actions: widget.profile.editable ? [
              TextButton(
                onPressed: _save,
                child: Text(locService.t('profileEditor.saveProfile')),
              ),
            ] : null,
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16, 
              16, 
              16, 
              16 + MediaQuery.of(context).padding.bottom,
            ),
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
                if (_requiresDirection) Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: TextField(
                    controller: _fovCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: locService.t('profileEditor.fov'),
                      hintText: locService.t('profileEditor.fovHint'),
                      helperText: locService.t('profileEditor.fovSubtitle'),
                      errorText: _validateFov(),
                      suffixText: '°',
                    ),
                    onChanged: (value) => setState(() {}), // Trigger validation
                  ),
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
                        onPressed: () => setState(() => _tags.insert(0, const MapEntry('', ''))),
                        icon: const Icon(Icons.add),
                        label: Text(locService.t('profileEditor.addTag')),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              ..._buildTagRows(),
              const SizedBox(height: 24),
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
              child: NSITagValueField(
                key: ValueKey('${_tags[i].key}_$i'), // Rebuild when key changes
                tagKey: _tags[i].key,
                initialValue: _tags[i].value,
                hintText: locService.t('profileEditor.valueHint'),
                readOnly: !widget.profile.editable,
                onChanged: !widget.profile.editable 
                    ? (v) {} // No-op when read-only
                    : (v) => setState(() => _tags[i] = MapEntry(_tags[i].key, v)),
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

  String? _validateFov() {
    final text = _fovCtrl.text.trim();
    if (text.isEmpty) return null; // Optional field
    
    final fov = double.tryParse(text);
    if (fov == null || fov <= 0 || fov > 360) {
      return LocalizationService.instance.t('profileEditor.fovInvalid');
    }
    return null;
  }

  void _save() {
    final locService = LocalizationService.instance;
    final name = _nameCtrl.text.trim();
    
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(locService.t('profileEditor.profileNameRequired'))));
      return;
    }

    // Validate FOV if provided
    if (_validateFov() != null) {
      return; // Don't save if FOV validation fails
    }

    // Parse FOV
    final fovText = _fovCtrl.text.trim();
    final fov = fovText.isEmpty ? null : double.tryParse(fovText);
    
    final tagMap = <String, String>{};
    for (final e in _tags) {
      if (e.key.trim().isEmpty) continue; // Skip only if key is empty
      tagMap[e.key.trim()] = e.value.trim(); // Allow empty values for refinement
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
      fov: fov,
    );
    
    context.read<AppState>().addOrUpdateProfile(newProfile);
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(locService.t('profileEditor.profileSaved', params: [newProfile.name]))),
    );
  }
}

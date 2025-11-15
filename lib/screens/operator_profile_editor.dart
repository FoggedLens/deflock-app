import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/operator_profile.dart';
import '../app_state.dart';
import '../services/localization_service.dart';

class OperatorProfileEditor extends StatefulWidget {
  const OperatorProfileEditor({super.key, required this.profile});

  final OperatorProfile profile;

  @override
  State<OperatorProfileEditor> createState() => _OperatorProfileEditorState();
}

class _OperatorProfileEditorState extends State<OperatorProfileEditor> {
  late TextEditingController _nameCtrl;
  late List<MapEntry<String, String>> _tags;

  static const _defaultTags = [
    MapEntry('operator', ''),
    MapEntry('operator:type', ''),
    MapEntry('operator:wikidata', ''),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile.name);

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
            title: Text(widget.profile.name.isEmpty ? locService.t('operatorProfileEditor.newOperatorProfile') : locService.t('operatorProfileEditor.editOperatorProfile')),
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
                decoration: InputDecoration(
                  labelText: locService.t('operatorProfileEditor.operatorName'),
                  hintText: locService.t('operatorProfileEditor.operatorNameHint'),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(locService.t('profileEditor.osmTags'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                onChanged: (v) => _tags[i] = MapEntry(v, _tags[i].value),
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
                onChanged: (v) => _tags[i] = MapEntry(_tags[i].key, v),
              ),
            ),
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
          .showSnackBar(SnackBar(content: Text(locService.t('operatorProfileEditor.operatorNameRequired'))));
      return;
    }
    
    final tagMap = <String, String>{};
    for (final e in _tags) {
      if (e.key.trim().isEmpty || e.value.trim().isEmpty) continue;
      tagMap[e.key.trim()] = e.value.trim();
    }
    
    final newProfile = widget.profile.copyWith(
      id: widget.profile.id.isEmpty ? const Uuid().v4() : widget.profile.id,
      name: name,
      tags: tagMap,
    );
    
    context.read<AppState>().addOrUpdateOperatorProfile(newProfile);
    Navigator.pop(context);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(locService.t('operatorProfileEditor.operatorProfileSaved', params: [newProfile.name]))),
    );
  }
}
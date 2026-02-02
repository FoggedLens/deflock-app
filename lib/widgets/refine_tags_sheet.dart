import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/operator_profile.dart';
import '../models/node_profile.dart';
import '../services/localization_service.dart';
import 'nsi_tag_value_field.dart';

/// Result returned from RefineTagsSheet
class RefineTagsResult {
  final OperatorProfile? operatorProfile;
  final Map<String, String> refinedTags;
  final Map<String, String>? editedTags; // For existing tags profile mode
  final String changesetComment; // User-editable changeset comment

  RefineTagsResult({
    required this.operatorProfile,
    required this.refinedTags,
    this.editedTags,
    required this.changesetComment,
  });
}

class RefineTagsSheet extends StatefulWidget {
  const RefineTagsSheet({
    super.key,
    this.selectedOperatorProfile,
    this.selectedProfile,
    this.currentRefinedTags,
    this.originalNodeTags,
    required this.operation,
  });

  final OperatorProfile? selectedOperatorProfile;
  final NodeProfile? selectedProfile;
  final Map<String, String>? currentRefinedTags;
  final Map<String, String>? originalNodeTags;
  final UploadOperation operation;

  @override
  State<RefineTagsSheet> createState() => _RefineTagsSheetState();
}

class _RefineTagsSheetState extends State<RefineTagsSheet> {
  OperatorProfile? _selectedOperatorProfile;
  Map<String, String> _refinedTags = {};
  
  // For existing tags profile: full tag editing
  late List<MapEntry<String, String>> _editableTags;
  
  // Changeset comment editing
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _selectedOperatorProfile = widget.selectedOperatorProfile;
    _refinedTags = Map<String, String>.from(widget.currentRefinedTags ?? {});
    
    // Pre-populate refined tags with existing node values for empty profile tags
    _prePopulateWithExistingValues();
    
    // Initialize editable tags for existing tags profile
    if (widget.selectedProfile?.isExistingTagsProfile == true) {
      _editableTags = widget.selectedProfile!.tags.entries.toList();
    } else {
      _editableTags = [];
    }
    
    // Initialize changeset comment with default
    final defaultComment = AppState.generateDefaultChangesetComment(
      profile: widget.selectedProfile,
      operation: widget.operation,
    );
    _commentController = TextEditingController(text: defaultComment);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Pre-populate refined tags with existing values from the original node
  void _prePopulateWithExistingValues() {
    if (widget.selectedProfile == null || widget.originalNodeTags == null) return;
    
    // Get refinable tags (empty values in profile)
    final refinableTags = _getRefinableTags();
    
    // For each refinable tag, check if original node has a value
    for (final tagKey in refinableTags) {
      // Only pre-populate if we don't already have a refined value for this tag
      if (!_refinedTags.containsKey(tagKey)) {
        final existingValue = widget.originalNodeTags![tagKey];
        if (existingValue != null && existingValue.trim().isNotEmpty) {
          _refinedTags[tagKey] = existingValue;
        }
      }
    }
  }

  /// Get list of tag keys that have empty values and can be refined
  List<String> _getRefinableTags() {
    if (widget.selectedProfile == null) return [];
    if (widget.selectedProfile!.isExistingTagsProfile) return []; // Use full editing mode instead
    
    return widget.selectedProfile!.tags.entries
        .where((entry) => entry.value.trim().isEmpty)
        .map((entry) => entry.key)
        .toList();
  }
  
  /// Returns true if this is the existing tags profile requiring full editing
  bool get _isExistingTagsMode => widget.selectedProfile?.isExistingTagsProfile == true;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final operatorProfiles = appState.operatorProfiles;
    final locService = LocalizationService.instance;
    
    // Check if we have an existing operator profile (from the selected profile)
    final hasExistingOperatorProfile = widget.selectedOperatorProfile?.isExistingOperatorProfile == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(locService.t('refineTagsSheet.title')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, RefineTagsResult(
            operatorProfile: widget.selectedOperatorProfile,
            refinedTags: widget.currentRefinedTags ?? {},
            editedTags: _isExistingTagsMode ? widget.selectedProfile?.tags : null,
            changesetComment: _commentController.text,
          )),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final editedTags = _isExistingTagsMode 
                  ? Map<String, String>.fromEntries(_editableTags.where((e) => e.key.isNotEmpty))
                  : null;
              
              Navigator.pop(context, RefineTagsResult(
                operatorProfile: _selectedOperatorProfile,
                refinedTags: _refinedTags,
                editedTags: editedTags,
                changesetComment: _commentController.text,
              ));
            },
            child: Text(locService.t('refineTagsSheet.done')),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Text(
            locService.t('refineTagsSheet.operatorProfile'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (operatorProfiles.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.grey, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      locService.t('refineTagsSheet.noOperatorProfiles'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      locService.t('refineTagsSheet.noOperatorProfilesMessage'),
                      style: const TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Card(
              child: Column(
                children: [
                  // Show existing operator profile first if it exists
                  if (hasExistingOperatorProfile) ...[
                    RadioListTile<OperatorProfile?>(
                      title: Text(locService.t('refineTagsSheet.existingOperator')),
                      subtitle: Text('${widget.selectedOperatorProfile!.tags.length} ${locService.t('refineTagsSheet.existingOperatorTags')}'),
                      value: widget.selectedOperatorProfile,
                      groupValue: _selectedOperatorProfile,
                      onChanged: (value) => setState(() => _selectedOperatorProfile = value),
                    ),
                    const Divider(height: 1),
                  ],
                  RadioListTile<OperatorProfile?>(
                    title: Text(locService.t('refineTagsSheet.none')),
                    subtitle: Text(locService.t('refineTagsSheet.noAdditionalOperatorTags')),
                    value: null,
                    groupValue: _selectedOperatorProfile,
                    onChanged: (value) => setState(() => _selectedOperatorProfile = value),
                  ),
                  ...operatorProfiles.map((profile) => RadioListTile<OperatorProfile?>(
                    title: Text(profile.name),
                    subtitle: Text('${profile.tags.length} ${locService.t('refineTagsSheet.additionalTags')}'),
                    value: profile,
                    groupValue: _selectedOperatorProfile,
                    onChanged: (value) => setState(() => _selectedOperatorProfile = value),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_selectedOperatorProfile != null) ...[
              Text(
                locService.t('refineTagsSheet.additionalTagsTitle'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedOperatorProfile!.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedOperatorProfile!.tags.isEmpty)
                        Text(
                          locService.t('refineTagsSheet.noTagsDefinedForProfile'),
                          style: const TextStyle(color: Colors.grey),
                        )
                      else
                        ...(_selectedOperatorProfile!.tags.entries.map((entry) => 
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    entry.key,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    entry.value,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                    ],
                  ),
                ),
              ),
            ],
          ],
          // Add refineable tags section OR existing tags editing section
          ...(_isExistingTagsMode 
              ? _buildExistingTagsEditingSection(locService)
              : _buildRefinableTagsSection(locService)),
          
          // Changeset comment section
          const SizedBox(height: 16),
          Text(
            'Change Comment',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              hintText: 'Describe your changes...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Build the section for refineable tags (empty-value profile tags)
  List<Widget> _buildRefinableTagsSection(LocalizationService locService) {
    final refinableTags = _getRefinableTags();
    if (refinableTags.isEmpty) {
      return [];
    }

    return [
      const SizedBox(height: 24),
      Text(
        locService.t('refineTagsSheet.profileTags'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locService.t('refineTagsSheet.profileTagsDescription'),
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ...refinableTags.map((tagKey) => _buildTagDropdown(tagKey, locService)),
            ],
          ),
        ),
      ),
    ];
  }

  /// Build a text field for a single refineable tag (similar to profile editor)
  Widget _buildTagDropdown(String tagKey, LocalizationService locService) {
    final currentValue = _refinedTags[tagKey] ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tagKey,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          NSITagValueField(
            key: ValueKey('${tagKey}_refine'),
            tagKey: tagKey,
            initialValue: currentValue,
            hintText: locService.t('refineTagsSheet.selectValue'),
            onChanged: (value) {
              setState(() {
                if (value.trim().isEmpty) {
                  _refinedTags.remove(tagKey);
                } else {
                  _refinedTags[tagKey] = value.trim();
                }
              });
            },
          ),
        ],
      ),
    );
  }

  /// Build the section for full tag editing (existing tags profile mode)
  List<Widget> _buildExistingTagsEditingSection(LocalizationService locService) {
    return [
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            locService.t('refineTagsSheet.existingTagsTitle'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: _addNewTag,
            tooltip: 'Add new tag',
          ),
        ],
      ),
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                locService.t('refineTagsSheet.existingTagsDescription'),
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (_editableTags.isEmpty)
                Text(
                  'No tags defined.',
                  style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                )
              else
                ..._editableTags.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tag = entry.value;
                  return _buildFullTagEditor(index, tag.key, tag.value, locService);
                }),
            ],
          ),
        ),
      ),
    ];
  }

  /// Build a full tag editor row with key, value, and delete button
  Widget _buildFullTagEditor(int index, String key, String value, LocalizationService locService) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          // Tag key field
          Expanded(
            flex: 2,
            child: TextFormField(
              initialValue: key,
              decoration: InputDecoration(
                labelText: 'Key',
                hintText: 'e.g., manufacturer',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (newKey) {
                setState(() {
                  _editableTags[index] = MapEntry(newKey, _editableTags[index].value);
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          // Tag value field (with NSI support)
          Expanded(
            flex: 3,
            child: NSITagValueField(
              key: ValueKey('${key}_${index}_edit'),
              tagKey: key,
              initialValue: value,
              hintText: 'Tag value',
              onChanged: (newValue) {
                setState(() {
                  _editableTags[index] = MapEntry(_editableTags[index].key, newValue);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          // Delete button
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
            onPressed: () => _removeTag(index),
            tooltip: 'Remove tag',
          ),
        ],
      ),
    );
  }

  /// Add a new empty tag
  void _addNewTag() {
    setState(() {
      _editableTags.add(const MapEntry('', ''));
    });
  }

  /// Remove a tag by index
  void _removeTag(int index) {
    setState(() {
      _editableTags.removeAt(index);
    });
  }
}
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
  final Map<String, String>? additionalExistingTags; // For tags that exist on node but not in selected profile
  final String changesetComment; // User-editable changeset comment

  RefineTagsResult({
    required this.operatorProfile,
    required this.refinedTags,
    this.additionalExistingTags,
    required this.changesetComment,
  });
}

class RefineTagsSheet extends StatefulWidget {
  const RefineTagsSheet({
    super.key,
    this.selectedOperatorProfile,
    this.selectedProfile,
    this.currentRefinedTags,
    this.currentAdditionalExistingTags,
    this.originalNodeTags,
    required this.operation,
  });

  final OperatorProfile? selectedOperatorProfile;
  final NodeProfile? selectedProfile;
  final Map<String, String>? currentRefinedTags;
  final Map<String, String>? currentAdditionalExistingTags;
  final Map<String, String>? originalNodeTags;
  final UploadOperation operation;

  @override
  State<RefineTagsSheet> createState() => _RefineTagsSheetState();
}

class _RefineTagsSheetState extends State<RefineTagsSheet> {
  OperatorProfile? _selectedOperatorProfile;
  Map<String, String> _refinedTags = {};
  

  
  // For additional existing tags (tags on node but not in profile)
  late List<MapEntry<String, String>> _additionalExistingTags;
  
  // Changeset comment editing
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _selectedOperatorProfile = widget.selectedOperatorProfile;
    _refinedTags = Map<String, String>.from(widget.currentRefinedTags ?? {});
    
    // Note: Pre-population is now handled by SessionState when profile changes
    // _refinedTags is already initialized with the session's refinedTags above
    

    
    // Initialize additional existing tags (tags on node but not in profile)
    _initializeAdditionalExistingTags();
    
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



  /// Get list of tag keys that have empty values and can be refined
  List<String> _getRefinableTags() {
    if (widget.selectedProfile == null) return [];
    
    return widget.selectedProfile!.tags.entries
        .where((entry) => entry.value.trim().isEmpty)
        .map((entry) => entry.key)
        .toList();
  }
  
  /// Initialize additional existing tags (tags that exist on the node but not in the selected profile)
  void _initializeAdditionalExistingTags() {
    // Use the additional existing tags calculated by SessionState when profile changed
    if (widget.currentAdditionalExistingTags != null) {
      _additionalExistingTags = widget.currentAdditionalExistingTags!.entries.toList();
      debugPrint('RefineTagsSheet: Loaded ${_additionalExistingTags.length} additional existing tags from session');
      return;
    }
    
    // Fallback: calculate them here if not provided (shouldn't normally happen)
    _additionalExistingTags = [];
    
    // Skip if we don't have the required data
    if (widget.originalNodeTags == null || widget.selectedProfile == null) {
      return;
    }
    
    // Get tags from the original node that are not in the selected profile
    final profileTagKeys = widget.selectedProfile!.tags.keys.toSet();
    final originalTags = widget.originalNodeTags!;
    
    for (final entry in originalTags.entries) {
      final key = entry.key;
      final value = entry.value;
      
      // Skip tags that are handled elsewhere
      if (_shouldSkipTag(key)) continue;
      
      // Skip tags that exist in the selected profile
      if (profileTagKeys.contains(key)) continue;
      
      // Include this tag as an additional existing tag
      _additionalExistingTags.add(MapEntry(key, value));
    }
    
    debugPrint('RefineTagsSheet: Fallback calculated ${_additionalExistingTags.length} additional existing tags');
  }
  
  /// Check if a tag should be skipped from additional existing tags
  bool _shouldSkipTag(String key) {
    // Skip direction tags (handled separately)
    if (key == 'direction' || key == 'camera:direction') return true;
    
    // Skip operator tags (handled by operator profile)
    if (key == 'operator' || key.startsWith('operator:')) return true;
    
    // Skip internal cache tags
    if (key.startsWith('_')) return true;
    
    return false;
  }

  /// Returns true if we should show the additional existing tags section
  bool get _shouldShowAdditionalExistingTags => _hasAdditionalExistingTagsToManage;
      
  /// Returns true if we have additional existing tags to manage (even if user deleted them all)
  bool get _hasAdditionalExistingTagsToManage {
    // Check if we originally had additional existing tags OR if user has added new ones
    if (widget.currentAdditionalExistingTags != null && widget.currentAdditionalExistingTags!.isNotEmpty) {
      return true; // We loaded some from the session
    }
    
    // Fallback: check if we calculated any from the original node
    if (widget.originalNodeTags != null && widget.selectedProfile != null) {
      final profileTagKeys = widget.selectedProfile!.tags.keys.toSet();
      final originalTags = widget.originalNodeTags!;
      
      for (final entry in originalTags.entries) {
        if (_shouldSkipTag(entry.key)) continue;
        if (profileTagKeys.contains(entry.key)) continue;
        return true; // Found at least one additional existing tag
      }
    }
    
    return false;
  }

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
            additionalExistingTags: _hasAdditionalExistingTagsToManage 
                ? Map<String, String>.fromEntries(_additionalExistingTags.where((e) => e.key.isNotEmpty))
                : null,
            changesetComment: _commentController.text,
          )),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final additionalTags = _hasAdditionalExistingTagsToManage 
                  ? Map<String, String>.fromEntries(_additionalExistingTags.where((e) => e.key.isNotEmpty))
                  : null;
              
              debugPrint('RefineTagsSheet: Returning result');
              debugPrint('RefineTagsSheet: additionalTags: $additionalTags');
              debugPrint('RefineTagsSheet: _additionalExistingTags: $_additionalExistingTags');
              debugPrint('RefineTagsSheet: _shouldShowAdditionalExistingTags: $_shouldShowAdditionalExistingTags');
              
              Navigator.pop(context, RefineTagsResult(
                operatorProfile: _selectedOperatorProfile,
                refinedTags: _refinedTags,
                additionalExistingTags: additionalTags,
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
          // Add refineable tags section
          ..._buildRefinableTagsSection(locService),
          
          // Add additional existing tags section
          ...(_shouldShowAdditionalExistingTags 
              ? _buildAdditionalExistingTagsSection(locService) 
              : []),
          
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



  /// Build the section for additional existing tags (tags on node but not in profile)
  List<Widget> _buildAdditionalExistingTagsSection(LocalizationService locService) {
    return [
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Additional Existing Tags',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: _addNewAdditionalTag,
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
                'These tags exist on the original node but are not part of the selected profile. You can edit or remove them.',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (_additionalExistingTags.isEmpty)
                Text(
                  'No additional existing tags.',
                  style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                )
              else
                ..._additionalExistingTags.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tag = entry.value;
                  return _buildAdditionalTagEditor(index, tag.key, tag.value, locService);
                }),
            ],
          ),
        ),
      ),
    ];
  }

  /// Build a tag editor row for additional existing tags
  Widget _buildAdditionalTagEditor(int index, String key, String value, LocalizationService locService) {
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
                  _additionalExistingTags[index] = MapEntry(newKey, _additionalExistingTags[index].value);
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          // Tag value field (with NSI support)
          Expanded(
            flex: 3,
            child: NSITagValueField(
              key: ValueKey('${key}_${index}_additional'),
              tagKey: key,
              initialValue: value,
              hintText: 'Tag value',
              onChanged: (newValue) {
                setState(() {
                  _additionalExistingTags[index] = MapEntry(_additionalExistingTags[index].key, newValue);
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          // Delete button
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
            onPressed: () => _removeAdditionalTag(index),
            tooltip: 'Remove tag',
          ),
        ],
      ),
    );
  }

  /// Add a new empty additional tag
  void _addNewAdditionalTag() {
    setState(() {
      _additionalExistingTags.add(const MapEntry('', ''));
    });
  }

  /// Remove an additional tag by index
  void _removeAdditionalTag(int index) {
    setState(() {
      _additionalExistingTags.removeAt(index);
    });
  }
}
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

  RefineTagsResult({
    required this.operatorProfile,
    required this.refinedTags,
  });
}

class RefineTagsSheet extends StatefulWidget {
  const RefineTagsSheet({
    super.key,
    this.selectedOperatorProfile,
    this.selectedProfile,
    this.currentRefinedTags,
  });

  final OperatorProfile? selectedOperatorProfile;
  final NodeProfile? selectedProfile;
  final Map<String, String>? currentRefinedTags;

  @override
  State<RefineTagsSheet> createState() => _RefineTagsSheetState();
}

class _RefineTagsSheetState extends State<RefineTagsSheet> {
  OperatorProfile? _selectedOperatorProfile;
  Map<String, String> _refinedTags = {};

  @override
  void initState() {
    super.initState();
    _selectedOperatorProfile = widget.selectedOperatorProfile;
    _refinedTags = Map<String, String>.from(widget.currentRefinedTags ?? {});
  }

  /// Get list of tag keys that have empty values and can be refined
  List<String> _getRefinableTags() {
    if (widget.selectedProfile == null) return [];
    
    return widget.selectedProfile!.tags.entries
        .where((entry) => entry.value.trim().isEmpty)
        .map((entry) => entry.key)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final operatorProfiles = appState.operatorProfiles;
    final locService = LocalizationService.instance;

    return Scaffold(
      appBar: AppBar(
        title: Text(locService.t('refineTagsSheet.title')),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, RefineTagsResult(
            operatorProfile: widget.selectedOperatorProfile,
            refinedTags: widget.currentRefinedTags ?? {},
          )),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, RefineTagsResult(
              operatorProfile: _selectedOperatorProfile,
              refinedTags: _refinedTags,
            )),
            child: Text(locService.t('refineTagsSheet.done')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
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
}
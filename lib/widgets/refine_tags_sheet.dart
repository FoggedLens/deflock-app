import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/operator_profile.dart';
import '../models/node_profile.dart';
import '../services/localization_service.dart';
import '../services/nsi_service.dart';

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
  Map<String, List<String>> _tagSuggestions = {};
  Map<String, bool> _loadingSuggestions = {};

  @override
  void initState() {
    super.initState();
    _selectedOperatorProfile = widget.selectedOperatorProfile;
    _refinedTags = Map<String, String>.from(widget.currentRefinedTags ?? {});
    _loadTagSuggestions();
  }

  /// Load suggestions for all empty-value tags in the selected profile
  void _loadTagSuggestions() async {
    if (widget.selectedProfile == null) return;

    final refinableTags = _getRefinableTags();
    
    for (final tagKey in refinableTags) {
      if (_tagSuggestions.containsKey(tagKey)) continue;
      
      setState(() {
        _loadingSuggestions[tagKey] = true;
      });

      try {
        final suggestions = await NSIService().getAllSuggestions(tagKey);
        if (mounted) {
          setState(() {
            _tagSuggestions[tagKey] = suggestions;
            _loadingSuggestions[tagKey] = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _tagSuggestions[tagKey] = [];
            _loadingSuggestions[tagKey] = false;
          });
        }
      }
    }
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

  /// Build a dropdown for a single refineable tag
  Widget _buildTagDropdown(String tagKey, LocalizationService locService) {
    final suggestions = _tagSuggestions[tagKey] ?? [];
    final isLoading = _loadingSuggestions[tagKey] ?? false;
    final currentValue = _refinedTags[tagKey];

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
          if (isLoading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Loading suggestions...', style: TextStyle(color: Colors.grey)),
              ],
            )
          else if (suggestions.isEmpty)
            DropdownButtonFormField<String>(
              value: currentValue?.isNotEmpty == true ? currentValue : null,
              decoration: InputDecoration(
                hintText: locService.t('refineTagsSheet.noSuggestions'),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [],
              onChanged: null, // Disabled when no suggestions
            )
          else
            DropdownButtonFormField<String>(
              value: currentValue?.isNotEmpty == true ? currentValue : null,
              decoration: InputDecoration(
                hintText: locService.t('refineTagsSheet.selectValue'),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(locService.t('refineTagsSheet.noValue'),
                      style: const TextStyle(color: Colors.grey)),
                ),
                ...suggestions.map((suggestion) => DropdownMenuItem<String>(
                  value: suggestion,
                  child: Text(suggestion),
                )),
              ],
              onChanged: (value) {
                setState(() {
                  if (value == null) {
                    _refinedTags.remove(tagKey);
                  } else {
                    _refinedTags[tagKey] = value;
                  }
                });
              },
            ),
        ],
      ),
    );
  }
}
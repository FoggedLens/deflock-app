import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/operator_profile.dart';
import '../services/localization_service.dart';

class RefineTagsSheet extends StatefulWidget {
  const RefineTagsSheet({
    super.key,
    this.selectedOperatorProfile,
  });

  final OperatorProfile? selectedOperatorProfile;

  @override
  State<RefineTagsSheet> createState() => _RefineTagsSheetState();
}

class _RefineTagsSheetState extends State<RefineTagsSheet> {
  OperatorProfile? _selectedOperatorProfile;

  @override
  void initState() {
    super.initState();
    _selectedOperatorProfile = widget.selectedOperatorProfile;
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
          onPressed: () => Navigator.pop(context, widget.selectedOperatorProfile),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selectedOperatorProfile),
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
        ],
      ),
    );
  }
}
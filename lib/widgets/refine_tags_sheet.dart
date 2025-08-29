import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/operator_profile.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Refine Tags'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, widget.selectedOperatorProfile),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selectedOperatorProfile),
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Operator Profile',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (operatorProfiles.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey, size: 48),
                    SizedBox(height: 8),
                    Text(
                      'No operator profiles defined',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Create operator profiles in Settings to apply additional tags to your node submissions.',
                      style: TextStyle(color: Colors.grey),
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
                    title: const Text('None'),
                    subtitle: const Text('No additional operator tags'),
                    value: null,
                    groupValue: _selectedOperatorProfile,
                    onChanged: (value) => setState(() => _selectedOperatorProfile = value),
                  ),
                  ...operatorProfiles.map((profile) => RadioListTile<OperatorProfile?>(
                    title: Text(profile.name),
                    subtitle: Text('${profile.tags.length} additional tags'),
                    value: profile,
                    groupValue: _selectedOperatorProfile,
                    onChanged: (value) => setState(() => _selectedOperatorProfile = value),
                  )),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_selectedOperatorProfile != null) ...[
              const Text(
                'Additional Tags',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                        const Text(
                          'No tags defined for this operator profile.',
                          style: TextStyle(color: Colors.grey),
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
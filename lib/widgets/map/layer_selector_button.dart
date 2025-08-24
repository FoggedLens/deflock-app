import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/tile_provider.dart';
import '../../services/offline_area_service.dart';

class LayerSelectorButton extends StatelessWidget {
  const LayerSelectorButton({super.key});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      onPressed: () => _showLayerSelector(context),
      child: const Icon(Icons.layers),
    );
  }

  void _showLayerSelector(BuildContext context) {
    // Check if any downloads are active
    final offlineService = OfflineAreaService();
    if (offlineService.hasActiveDownloads) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot change tile types while downloading offline areas'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => const _LayerSelectorDialog(),
    );
  }
}

class _LayerSelectorDialog extends StatefulWidget {
  const _LayerSelectorDialog();

  @override
  State<_LayerSelectorDialog> createState() => _LayerSelectorDialogState();
}

class _LayerSelectorDialogState extends State<_LayerSelectorDialog> {
  String? _selectedTileTypeId;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _selectedTileTypeId = appState.selectedTileType?.id;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final providers = appState.tileProviders;

    // Group tile types by provider for display
    final providerGroups = <TileProvider, List<TileType>>{};
    for (final provider in providers) {
      final availableTypes = provider.availableTileTypes;
      if (availableTypes.isNotEmpty) {
        providerGroups[provider] = availableTypes;
      }
    }

    return Dialog(
      child: Container(
        width: double.maxFinite,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.layers),
                  const SizedBox(width: 8),
                  const Text(
                    'Select Map Layer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  if (providerGroups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No tile providers available'),
                      ),
                    )
                  else
                    ...providerGroups.entries.map((entry) {
                      final provider = entry.key;
                      final tileTypes = entry.value;
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Provider header
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Theme.of(context).colorScheme.surface,
                            child: Text(
                              provider.name,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          // Tile types
                          ...tileTypes.map((tileType) => _TileTypeListItem(
                            tileType: tileType,
                            provider: provider,
                            isSelected: _selectedTileTypeId == tileType.id,
                            onSelected: () {
                              setState(() {
                                _selectedTileTypeId = tileType.id;
                              });
                              appState.setSelectedTileType(tileType.id);
                              Navigator.of(context).pop();
                            },
                          )),
                        ],
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TileTypeListItem extends StatelessWidget {
  final TileType tileType;
  final TileProvider provider;
  final bool isSelected;
  final VoidCallback onSelected;

  const _TileTypeListItem({
    required this.tileType,
    required this.provider,
    required this.isSelected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected 
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: tileType.previewTile != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.memory(
                  tileType.previewTile!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _FallbackPreview(),
                ),
              )
            : _FallbackPreview(),
      ),
      title: Text(
        tileType.name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : null,
          color: isSelected ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        tileType.attribution,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: isSelected 
          ? Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
      onTap: onSelected,
    );
  }
}

class _FallbackPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade200,
      child: const Center(
        child: Icon(
          Icons.map,
          size: 24,
          color: Colors.grey,
        ),
      ),
    );
  }
}
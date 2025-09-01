import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/tile_provider.dart';
import '../services/localization_service.dart';
import 'tile_provider_editor_screen.dart';

class TileProviderManagementScreen extends StatelessWidget {
  const TileProviderManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        final providers = appState.tileProviders;

        return Scaffold(
          appBar: AppBar(
            title: Text(locService.t('tileProviders.title')),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _addProvider(context),
              ),
            ],
          ),
          body: providers.isEmpty
              ? Center(
                  child: Text(locService.t('tileProviders.noProvidersConfigured')),
                )
              : ListView.builder(
                  itemCount: providers.length,
                  itemBuilder: (context, index) {
                    final provider = providers[index];
                    final isSelected = appState.selectedTileProvider?.id == provider.id;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        title: Text(
                          provider.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : null,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(locService.t('tileProviders.tileTypesCount', params: [provider.tileTypes.length.toString()])),
                            if (provider.apiKey?.isNotEmpty == true)
                              Text(
                                locService.t('tileProviders.apiKeyConfigured'),
                                style: const TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 12,
                                ),
                              ),
                            if (!provider.isUsable)
                              Text(
                                locService.t('tileProviders.needsApiKey'),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                        leading: CircleAvatar(
                          backgroundColor: isSelected 
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceVariant,
                          child: Icon(
                            Icons.map,
                            color: isSelected 
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: providers.length > 1 
                            ? PopupMenuButton<String>(
                                onSelected: (action) {
                                  switch (action) {
                                    case 'edit':
                                      _editProvider(context, provider);
                                      break;
                                    case 'delete':
                                      _deleteProvider(context, provider);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.edit),
                                        const SizedBox(width: 8),
                                        Text(locService.t('actions.edit')),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        const Icon(Icons.delete),
                                        const SizedBox(width: 8),
                                        Text(locService.t('tileProviders.deleteProvider')),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : const Icon(Icons.lock, size: 16), // Can't delete last provider
                        onTap: () => _editProvider(context, provider),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  void _addProvider(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TileProviderEditorScreen(),
      ),
    );
  }

  void _editProvider(BuildContext context, TileProvider provider) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TileProviderEditorScreen(provider: provider),
      ),
    );
  }

  void _deleteProvider(BuildContext context, TileProvider provider) {
    final locService = LocalizationService.instance;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locService.t('tileProviders.deleteProvider')),
        content: Text(locService.t('tileProviders.deleteProviderConfirm', params: [provider.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(locService.t('actions.cancel')),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteTileProvider(provider.id);
              Navigator.of(context).pop();
            },
            child: Text(locService.t('tileProviders.deleteProvider')),
          ),
        ],
      ),
    );
  }
}
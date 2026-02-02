import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../models/tile_provider.dart';
import '../../../services/localization_service.dart';
import '../../tile_provider_editor_screen.dart';

class TileProviderSection extends StatelessWidget {
  const TileProviderSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        final providers = appState.tileProviders;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  locService.t('mapTiles.title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton.icon(
                  onPressed: () => _addProvider(context),
                  icon: const Icon(Icons.add),
                  label: Text(locService.t('tileProviders.addProvider')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (providers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(locService.t('tileProviders.noProvidersConfigured')),
                ),
              )
            else
              ...providers.map((provider) => _buildProviderTile(context, provider, appState)),
          ],
        );
      },
    );
  }

  Widget _buildProviderTile(BuildContext context, TileProvider provider, AppState appState) {
    final locService = LocalizationService.instance;
    final isSelected = appState.selectedTileProvider?.id == provider.id;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
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
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Icon(
            Icons.map,
            color: isSelected 
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: appState.tileProviders.length > 1 
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
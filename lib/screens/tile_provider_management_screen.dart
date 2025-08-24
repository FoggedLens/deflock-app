import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/tile_provider.dart';
import 'tile_provider_editor_screen.dart';

class TileProviderManagementScreen extends StatelessWidget {
  const TileProviderManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final providers = appState.tileProviders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tile Providers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addProvider(context),
          ),
        ],
      ),
      body: providers.isEmpty
          ? const Center(
              child: Text('No tile providers configured'),
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
                        Text('${provider.tileTypes.length} tile types'),
                        if (provider.apiKey?.isNotEmpty == true)
                          const Text(
                            'API Key configured',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          ),
                        if (!provider.isUsable)
                          Text(
                            'Needs API key',
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
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit),
                                    SizedBox(width: 8),
                                    Text('Edit'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete),
                                    SizedBox(width: 8),
                                    Text('Delete'),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Provider'),
        content: Text('Are you sure you want to delete "${provider.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppState>().deleteTileProvider(provider.id);
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
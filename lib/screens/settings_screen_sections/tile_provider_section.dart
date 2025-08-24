import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/tile_provider.dart';

class TileProviderSection extends StatelessWidget {
  const TileProviderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final selectedTileType = appState.selectedTileType;
    final allTileTypes = <TileType>[];
    for (final provider in appState.tileProviders) {
      allTileTypes.addAll(provider.availableTileTypes);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Map Type',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton(
              onPressed: () {
                // TODO: Navigate to provider management screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Provider management coming soon!')),
                );
              },
              child: const Text('Manage Providers'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (allTileTypes.isEmpty)
          const Text('No tile providers available')
        else
          ...allTileTypes.map((tileType) {
            final provider = appState.tileProviders
                .firstWhere((p) => p.tileTypes.contains(tileType));
            final isSelected = selectedTileType?.id == tileType.id;
            final isUsable = !tileType.requiresApiKey || provider.isUsable;
            
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Radio<String>(
                value: tileType.id,
                groupValue: selectedTileType?.id,
                onChanged: isUsable ? (String? value) {
                  if (value != null) {
                    appState.setSelectedTileType(value);
                  }
                } : null,
              ),
              title: Text(
                '${provider.name} - ${tileType.name}',
                style: TextStyle(
                  color: isUsable ? null : Theme.of(context).disabledColor,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tileType.attribution,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isUsable ? null : Theme.of(context).disabledColor,
                    ),
                  ),
                  if (!isUsable)
                    Text(
                      'Requires API key',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
              onTap: isUsable ? () {
                appState.setSelectedTileType(tileType.id);
              } : null,
            );
          }),
      ],
    );
  }
}
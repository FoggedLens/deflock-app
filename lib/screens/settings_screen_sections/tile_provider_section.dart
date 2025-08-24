import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/tile_provider.dart';

class TileProviderSection extends StatelessWidget {
  const TileProviderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final currentProvider = appState.tileProvider;
    
    // Get available providers (for now, all free ones are available)
    final availableProviders = [
      TileProviders.osmStreet,
      TileProviders.googleHybrid,
      TileProviders.arcgisSatellite,
      // Don't include Mapbox for now since we don't have API key handling
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Map Type',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        ...availableProviders.map((config) {
          final isSelected = config.type == currentProvider;
          
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Radio<TileProviderType>(
              value: config.type,
              groupValue: currentProvider,
              onChanged: (TileProviderType? value) {
                if (value != null) {
                  appState.setTileProvider(value);
                }
              },
            ),
            title: Text(config.name),
            subtitle: config.description != null 
                ? Text(
                    config.description!,
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                : null,
            onTap: () {
              appState.setTileProvider(config.type);
            },
          );
        }),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/tile_provider.dart';
import '../tile_provider_management_screen.dart';

class TileProviderSection extends StatelessWidget {
  const TileProviderSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Map Tiles',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const TileProviderManagementScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('Manage Providers'),
          ),
        ),
      ],
    );
  }
}
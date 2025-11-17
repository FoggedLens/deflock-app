import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/suspected_location.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import '../dev_config.dart';

class SuspectedLocationSheet extends StatelessWidget {
  final SuspectedLocation location;

  const SuspectedLocationSheet({super.key, required this.location});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final appState = context.watch<AppState>();
        final locService = LocalizationService.instance;



        // Get all fields except location and ticket_no
        final displayData = <String, String>{};
        for (final entry in location.allFields.entries) {
          final value = entry.value?.toString();
          if (value != null && value.isNotEmpty) {
            displayData[entry.key] = value;
          }
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locService.t('suspectedLocation.title', params: [location.ticketNo]),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  
                  // Constrain field list height to keep buttons visible
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * kMaxTagListHeightRatio,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Display all fields
                          ...displayData.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: e.key.toLowerCase().contains('url') && e.value.isNotEmpty
                                ? GestureDetector(
                                    onTap: () async {
                                      final uri = Uri.parse(e.value);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                                      } else {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Could not open URL: ${e.value}'),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: Text(
                                      e.value,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                      softWrap: true,
                                    ),
                                  )
                                : Text(
                                    e.value,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                    softWrap: true,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Coordinates info
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          locService.t('suspectedLocation.coordinates'),
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${location.centroid.latitude.toStringAsFixed(6)}, ${location.centroid.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            ),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Close button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(locService.t('actions.close')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
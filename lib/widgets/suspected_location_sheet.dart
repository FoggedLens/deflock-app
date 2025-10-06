import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/suspected_location.dart';
import '../app_state.dart';
import '../services/localization_service.dart';

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

        Future<void> _launchUrl() async {
          if (location.urlFull?.isNotEmpty == true) {
            final uri = Uri.parse(location.urlFull!);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not open URL: ${location.urlFull}'),
                  ),
                );
              }
            }
          }
        }

        // Create display data map
        final Map<String, String?> displayData = {
          'Ticket No': location.ticketNo,
          'Address': location.addr,
          'Street': location.street,
          'City': location.city,
          'State': location.state,
          'Intersecting Street': location.digSiteIntersectingStreet,
          'Work Done For': location.digWorkDoneFor,
          'Remarks': location.digSiteRemarks,
          'URL': location.urlFull,
        };

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suspected Location #${location.ticketNo}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  
                  // Display all fields
                  ...displayData.entries.where((e) => e.value?.isNotEmpty == true).map(
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
                            child: e.key == 'URL' && e.value?.isNotEmpty == true
                                ? GestureDetector(
                                    onTap: _launchUrl,
                                    child: Text(
                                      e.value!,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                      softWrap: true,
                                    ),
                                  )
                                : Text(
                                    e.value ?? '',
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
                          'Coordinates',
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
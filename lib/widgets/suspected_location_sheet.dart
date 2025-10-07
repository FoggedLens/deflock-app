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

        // Create display data map using localized labels
        final Map<String, String?> displayData = {
          locService.t('suspectedLocation.ticketNo'): location.ticketNo,
          locService.t('suspectedLocation.address'): location.addr,
          locService.t('suspectedLocation.street'): location.street,
          locService.t('suspectedLocation.city'): location.city,
          locService.t('suspectedLocation.state'): location.state,
          locService.t('suspectedLocation.intersectingStreet'): location.digSiteIntersectingStreet,
          locService.t('suspectedLocation.workDoneFor'): location.digWorkDoneFor,
          locService.t('suspectedLocation.remarks'): location.digSiteRemarks,
          locService.t('suspectedLocation.url'): location.urlFull,
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
                    locService.t('suspectedLocation.title', params: [location.ticketNo]),
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
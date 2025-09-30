import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app_state.dart';
import '../../../services/localization_service.dart';

class UploadModeSection extends StatelessWidget {
  const UploadModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: Text(locService.t('uploadMode.title')),
              subtitle: Text(locService.t('uploadMode.subtitle')),
              trailing: DropdownButton<UploadMode>(
                value: appState.uploadMode,
                items: [
                  DropdownMenuItem(
                    value: UploadMode.production,
                    child: Text(locService.t('uploadMode.production')),
                  ),
                  DropdownMenuItem(
                    value: UploadMode.sandbox,
                    child: Text(locService.t('uploadMode.sandbox')),
                  ),
                  DropdownMenuItem(
                    value: UploadMode.simulate,
                    child: Text(locService.t('uploadMode.simulate')),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) appState.setUploadMode(mode);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 2, right: 16, bottom: 12),
              child: Builder(
                builder: (context) {
                  switch (appState.uploadMode) {
                    case UploadMode.production:
                      return Text(
                        locService.t('uploadMode.productionDescription'), 
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))
                      );
                    case UploadMode.sandbox:
                      return Text(
                        locService.t('uploadMode.sandboxDescription'),
                        style: const TextStyle(fontSize: 12, color: Colors.orange),
                      );
                    case UploadMode.simulate:
                    default:
                      return Text(
                        locService.t('uploadMode.simulateDescription'), 
                        style: const TextStyle(fontSize: 12, color: Colors.deepPurple)
                      );
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

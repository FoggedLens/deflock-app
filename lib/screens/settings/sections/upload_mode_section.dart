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
                onChanged: appState.pendingCount > 0 ? null : (mode) {
                  if (mode != null) {
                    appState.setUploadMode(mode);
                    // Check if re-authentication is needed after mode change
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      appState.checkAndPromptReauthForMessages(context);
                    });
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 2, right: 16, bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Upload mode restriction message when queue has items
                  if (appState.pendingCount > 0) ...[
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.orange, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            locService.t('uploadMode.cannotChangeWithQueue', params: [appState.pendingCount.toString()]),
                            style: const TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                  
                  // Normal upload mode description
                  Builder(
                    builder: (context) {
                      switch (appState.uploadMode) {
                        case UploadMode.production:
                          return Text(
                            locService.t('uploadMode.productionDescription'), 
                            style: TextStyle(
                              fontSize: 12, 
                              color: appState.pendingCount > 0 
                                ? Theme.of(context).disabledColor
                                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)
                            )
                          );
                        case UploadMode.sandbox:
                          return Text(
                            locService.t('uploadMode.sandboxDescription'),
                            style: TextStyle(
                              fontSize: 12, 
                              color: appState.pendingCount > 0 
                                ? Theme.of(context).disabledColor
                                : Colors.orange
                            ),
                          );
                        case UploadMode.simulate:
                          return Text(
                            locService.t('uploadMode.simulateDescription'), 
                            style: TextStyle(
                              fontSize: 12, 
                              color: appState.pendingCount > 0 
                                ? Theme.of(context).disabledColor
                                : Colors.deepPurple
                            )
                          );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

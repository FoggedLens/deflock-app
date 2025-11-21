import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import '../dev_config.dart';
import '../state/settings_state.dart';
import '../screens/settings/sections/upload_mode_section.dart';

class OSMAccountScreen extends StatelessWidget {
  const OSMAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();
        
        return Scaffold(
          appBar: AppBar(
            title: Text(locService.t('auth.osmAccountTitle')),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16, 
              16, 
              16, 
              16 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              // Login/Account Status Section
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        appState.isLoggedIn ? Icons.person : Icons.login,
                        color: appState.isLoggedIn ? Colors.green : null,
                      ),
                      title: Text(appState.isLoggedIn
                          ? locService.t('auth.loggedInAs', params: [appState.username])
                          : locService.t('auth.loginToOSM')),
                      subtitle: appState.isLoggedIn
                          ? Text(locService.t('auth.tapToLogout'))
                          : Text(locService.t('auth.requiredToSubmit')),
                      onTap: () async {
                        if (appState.isLoggedIn) {
                          await appState.logout();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(locService.t('auth.loggedOut')),
                                backgroundColor: Colors.grey,
                              ),
                            );
                          }
                        } else {
                          // Start login flow - the user will be redirected to browser
                          await appState.forceLogin();
                          
                          // Don't show immediate feedback - the UI will update automatically
                          // when the OAuth callback completes and notifyListeners() is called
                        }
                      },
                    ),
                    
                    if (appState.isLoggedIn) ...[
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.wifi_protected_setup),
                        title: Text(locService.t('auth.testConnection')),
                        subtitle: Text(locService.t('auth.testConnectionSubtitle')),
                        onTap: () async {
                          final isValid = await appState.validateToken();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(isValid
                                    ? locService.t('auth.connectionOK')
                                    : locService.t('auth.connectionFailed')),
                                backgroundColor: isValid ? Colors.green : Colors.red,
                              ),
                            );
                          }
                          if (!isValid) {
                            await appState.logout();
                          }
                        },
                      ),
                      
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(locService.t('auth.viewMyEdits')),
                        subtitle: Text(locService.t('auth.viewMyEditsSubtitle')),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () async {
                          final url = Uri.parse('https://openstreetmap.org/user/${Uri.encodeComponent(appState.username)}/history');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(locService.t('advancedEdit.couldNotOpenOSMWebsite'))),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Upload Mode Section (only show in development builds)
              if (kEnableDevelopmentModes) ...[
                Card(
                  child: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: UploadModeSection(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Information Section
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        locService.t('auth.aboutOSM'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        locService.t('auth.aboutOSMDescription'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final url = Uri.parse('https://openstreetmap.org');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url, mode: LaunchMode.externalApplication);
                            } else {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(locService.t('advancedEdit.couldNotOpenOSMWebsite'))),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: Text(locService.t('auth.visitOSM')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
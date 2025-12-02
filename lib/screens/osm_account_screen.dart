import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import '../dev_config.dart';
import '../screens/settings/sections/upload_mode_section.dart';

class OSMAccountScreen extends StatefulWidget {
  const OSMAccountScreen({super.key});

  @override
  State<OSMAccountScreen> createState() => _OSMAccountScreenState();
}

class _OSMAccountScreenState extends State<OSMAccountScreen> {
  @override
  void initState() {
    super.initState();
    // Check for messages when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = context.read<AppState>();
      if (appState.isLoggedIn) {
        appState.checkMessages();
      }
    });
  }

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
                      
                      // Only show OSM website buttons when not in simulate mode
                      if (appState.uploadMode != UploadMode.simulate) ...[
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
                        
                        // Messages button - only show when not in simulate mode
                        const Divider(),
                      ListTile(
                        leading: Stack(
                          children: [
                            const Icon(Icons.message),
                            if (appState.hasUnreadMessages)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 12,
                                    minHeight: 12,
                                  ),
                                  child: Text(
                                    '${appState.unreadMessageCount}',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.onError,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        title: Text(locService.t('auth.viewMessages')),
                        subtitle: Text(appState.hasUnreadMessages
                            ? locService.t('auth.unreadMessagesCount', params: [appState.unreadMessageCount.toString()])
                            : locService.t('auth.noUnreadMessages')),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () async {
                          final url = Uri.parse(appState.getMessagesUrl());
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
              
              // Account deletion section - only show when logged in and not in simulate mode
              if (appState.isLoggedIn && appState.uploadMode != UploadMode.simulate) ...[
                const SizedBox(height: 16),
                _buildAccountDeletionSection(context, appState),
              ],
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildAccountDeletionSection(BuildContext context, AppState appState) {
    final locService = LocalizationService.instance;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              locService.t('auth.accountManagement'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              locService.t('auth.accountManagementDescription'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            
            // Show current upload destination
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getCurrentDestinationText(locService, appState.uploadMode),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Delete account button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showDeleteAccountDialog(context, locService, appState.uploadMode),
                icon: const Icon(Icons.delete_outline),
                label: Text(locService.t('auth.deleteAccount')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error.withOpacity(0.5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _getCurrentDestinationText(LocalizationService locService, UploadMode uploadMode) {
    switch (uploadMode) {
      case UploadMode.production:
        return locService.t('auth.currentDestinationProduction');
      case UploadMode.sandbox:
        return locService.t('auth.currentDestinationSandbox');
      case UploadMode.simulate:
        return locService.t('auth.currentDestinationSimulate');
    }
  }
  
  void _showDeleteAccountDialog(BuildContext context, LocalizationService locService, UploadMode uploadMode) {
    final deleteUrl = _getDeleteAccountUrl(uploadMode);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(locService.t('auth.deleteAccount')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(locService.t('auth.deleteAccountExplanation')),
            const SizedBox(height: 12),
            Text(
              locService.t('auth.deleteAccountWarning'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 12),
            // Show which account will be deleted
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.3),
                ),
              ),
              child: Text(
                _getCurrentDestinationText(locService, uploadMode),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(locService.t('actions.cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _launchDeleteAccountUrl(deleteUrl, context, locService);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(locService.t('auth.goToOSM')),
          ),
        ],
      ),
    );
  }
  
  String _getDeleteAccountUrl(UploadMode uploadMode) {
    switch (uploadMode) {
      case UploadMode.production:
        return 'https://www.openstreetmap.org/account/deletion';
      case UploadMode.sandbox:
        return 'https://master.apis.dev.openstreetmap.org/account/deletion';
      case UploadMode.simulate:
        // For simulate mode, just go to production since it's not a real account
        return 'https://www.openstreetmap.org/account/deletion';
    }
  }
  
  Future<void> _launchDeleteAccountUrl(String url, BuildContext context, LocalizationService locService) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(locService.t('advancedEdit.couldNotOpenOSMWebsite')),
          ),
        );
      }
    }
  }
}
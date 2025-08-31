import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../services/localization_service.dart';

class AuthSection extends StatelessWidget {
  const AuthSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        final appState = context.watch<AppState>();

        return Column(
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
                } else {
                  await appState.forceLogin();
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(appState.isLoggedIn
                          ? locService.t('auth.loggedInAs', params: [appState.username])
                          : locService.t('auth.loggedOut')),
                      backgroundColor: appState.isLoggedIn ? Colors.green : Colors.grey,
                    ),
                  );
                }
              },
            ),
            if (appState.isLoggedIn)
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
          ],
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

class AuthSection extends StatelessWidget {
  const AuthSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return Column(
      children: [
        ListTile(
          leading: Icon(
            appState.isLoggedIn ? Icons.person : Icons.login,
            color: appState.isLoggedIn ? Colors.green : null,
          ),
          title: Text(appState.isLoggedIn
              ? 'Logged in as ${appState.username}'
              : 'Log in to OpenStreetMap'),
          subtitle: appState.isLoggedIn
              ? const Text('Tap to logout')
              : const Text('Required to submit camera data'),
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
                      ? 'Logged in as ${appState.username}'
                      : 'Logged out'),
                  backgroundColor: appState.isLoggedIn ? Colors.green : Colors.grey,
                ),
              );
            }
          },
        ),
        if (appState.isLoggedIn)
          ListTile(
            leading: const Icon(Icons.wifi_protected_setup),
            title: const Text('Test Connection'),
            subtitle: const Text('Verify OSM credentials are working'),
            onTap: () async {
              final isValid = await appState.validateToken();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isValid
                        ? 'Connection OK - credentials are valid'
                        : 'Connection failed - please re-login'),
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
  }
}

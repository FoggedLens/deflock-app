import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profiles_settings_screen.dart';
import 'screens/navigation_settings_screen.dart';
import 'screens/offline_settings_screen.dart';
import 'screens/advanced_settings_screen.dart';
import 'screens/language_settings_screen.dart';
import 'screens/about_screen.dart';
import 'services/localization_service.dart';
import 'services/version_service.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize version service
  await VersionService().init();
  
  // Initialize localization service
  await LocalizationService.instance.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          if (!appState.isInitialized) {
            // You can customize this splash/loading screen as needed
            return MaterialApp(
              home: Scaffold(
                backgroundColor: Color(0xFF152131),
                body: Center(
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 240,
                    height: 240,
                  ),
                ),
              ),
            );
          }
          return const DeFlockApp();
        },
      ),
    ),
  );
}

class DeFlockApp extends StatelessWidget {
  const DeFlockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeFlock',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0080BC), // DeFlock blue
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routes: {
        '/': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/settings/profiles': (context) => const ProfilesSettingsScreen(),
        '/settings/navigation': (context) => const NavigationSettingsScreen(),
        '/settings/offline': (context) => const OfflineSettingsScreen(),
        '/settings/advanced': (context) => const AdvancedSettingsScreen(),
        '/settings/language': (context) => const LanguageSettingsScreen(),
        '/settings/about': (context) => const AboutScreen(),
      },
      initialRoute: '/',
    );
  }
}


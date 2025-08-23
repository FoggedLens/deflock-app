import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';



Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          if (!appState.isInitialized) {
            // You can customize this splash/loading screen as needed
            return MaterialApp(
              home: Scaffold(
                backgroundColor: Color(0xFF202020),
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
          return const FlockMapApp();
        },
      ),
    ),
  );
}

class FlockMapApp extends StatelessWidget {
  const FlockMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flock Map',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      routes: {
        '/': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
      initialRoute: '/',
    );
  }
}


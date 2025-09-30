import 'package:flutter/material.dart';
import '../services/localization_service.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final locService = LocalizationService.instance;
    
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) => Scaffold(
        appBar: AppBar(
          title: Text(locService.t('settings.aboutThisApp')),
        ),
        body: FutureBuilder<String>(
          future: DefaultAssetBundle.of(context).loadString('assets/info.txt'),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }
            
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading info: ${snapshot.error}',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                snapshot.data ?? 'No info available.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          },
        ),
      ),
    );
  }
}
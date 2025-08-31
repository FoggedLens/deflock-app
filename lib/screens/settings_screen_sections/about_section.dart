import 'package:flutter/material.dart';
import '../../services/localization_service.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(locService.t('settings.aboutInfo')),
          onTap: () async {
            showDialog(
              context: context,
              builder: (context) => FutureBuilder<String>(
                future: DefaultAssetBundle.of(context).loadString('assets/info.txt'),
                builder: (context, snapshot) => AlertDialog(
                  title: Text(locService.t('settings.aboutThisApp')),
                  content: SingleChildScrollView(
                    child: Text(
                      snapshot.connectionState == ConnectionState.done
                          ? (snapshot.data ?? 'No info available.')
                          : 'Loading...',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(locService.ok),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

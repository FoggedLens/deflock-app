import 'package:flutter/material.dart';

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('About / Info'),
      onTap: () async {
        showDialog(
          context: context,
          builder: (context) => FutureBuilder<String>(
            future: DefaultAssetBundle.of(context).loadString('assets/info.txt'),
            builder: (context, snapshot) => AlertDialog(
              title: const Text('About This App'),
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
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

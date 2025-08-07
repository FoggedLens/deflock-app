import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

class UploadModeSection extends StatelessWidget {
  const UploadModeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_upload),
          title: const Text('Upload Destination'),
          subtitle: const Text('Choose where cameras are uploaded'),
          trailing: DropdownButton<UploadMode>(
            value: appState.uploadMode,
            items: const [
              DropdownMenuItem(
                value: UploadMode.production,
                child: Text('Production'),
              ),
              DropdownMenuItem(
                value: UploadMode.sandbox,
                child: Text('Sandbox'),
              ),
              DropdownMenuItem(
                value: UploadMode.simulate,
                child: Text('Simulate'),
              ),
            ],
            onChanged: (mode) {
              if (mode != null) appState.setUploadMode(mode);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 56, top: 2, right: 16, bottom: 12),
          child: Builder(
            builder: (context) {
              switch (appState.uploadMode) {
                case UploadMode.production:
                  return const Text('Upload to the live OSM database (visible to all users)', style: TextStyle(fontSize: 12, color: Colors.black87));
                case UploadMode.sandbox:
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Uploads go to the OSM Sandbox (safe for testing, resets regularly).',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'NOTE: Due to OpenStreetMap limitations, cameras submitted to the sandbox will NOT appear on the map in this app.',
                        style: TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ],
                  );
                case UploadMode.simulate:
                default:
                  return const Text('Simulate uploads (does not contact OSM servers)', style: TextStyle(fontSize: 12, color: Colors.deepPurple));
              }
            },
          ),
        ),
      ],
    );
  }
}

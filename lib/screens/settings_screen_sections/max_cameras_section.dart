import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';

class MaxCamerasSection extends StatefulWidget {
  const MaxCamerasSection({super.key});

  @override
  State<MaxCamerasSection> createState() => _MaxCamerasSectionState();
}

class _MaxCamerasSectionState extends State<MaxCamerasSection> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final maxCameras = context.read<AppState>().maxCameras;
    _controller = TextEditingController(text: maxCameras.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final current = appState.maxCameras;
    final showWarning = current > 1000;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.filter_alt),
          title: const Text('Max cameras fetched/drawn'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Set an upper limit for the number of cameras on the map (default: 250).'),
              if (showWarning)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: const [
                      Icon(Icons.warning, color: Colors.orange, size: 18),
                      SizedBox(width: 6),
                      Expanded(child: Text(
                        'You probably don\'t want to do that unless you are absolutely sure you have a good reason for it.',
                        style: TextStyle(color: Colors.orange),
                      )),
                    ],
                  ),
                ),
            ],
          ),
          trailing: SizedBox(
            width: 80,
            child: TextFormField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                border: OutlineInputBorder(),
              ),
              onFieldSubmitted: (value) {
                final n = int.tryParse(value) ?? 10;
                appState.maxCameras = n;
                _controller.text = appState.maxCameras.toString();
              },
            ),
          ),
        ),
      ],
    );
  }
}

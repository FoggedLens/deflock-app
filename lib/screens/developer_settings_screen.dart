import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../dev_config.dart';

class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  State<DeveloperSettingsScreen> createState() => _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _overrides = {};

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _initializeControllers() {
    for (final entry in devConfigForSettings.entries) {
      if (entry.value is String) {
        _controllers[entry.key] = TextEditingController(text: entry.value);
      } else if (entry.value is int) {
        _controllers[entry.key] = TextEditingController(text: entry.value.toString());
      } else if (entry.value is double) {
        _controllers[entry.key] = TextEditingController(text: entry.value.toString());
      } else if (entry.value is Color) {
        final color = entry.value as Color;
        final hex = color.value.toRadixString(16).padLeft(8, '0').toUpperCase();
        _controllers[entry.key] = TextEditingController(text: hex);
      } else if (entry.value is Duration) {
        final duration = entry.value as Duration;
        _controllers[entry.key] = TextEditingController(text: duration.inMilliseconds.toString());
      }
    }
  }

  void _saveAndRestart() {
    // For now, just show a dialog - actual restart would require platform channels
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart Required'),
        content: const Text('Changes saved. Please restart the app to apply new settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingWidget(String key, dynamic defaultValue) {
    if (key == 'kClientName') {
      // Special read-only case
      return ListTile(
        title: Text(key),
        subtitle: Text(defaultValue.toString()),
        trailing: const Text('READ ONLY'),
      );
    }

    if (defaultValue is bool) {
      return SwitchListTile(
        title: Text(key),
        value: _overrides[key] ?? defaultValue,
        onChanged: (value) {
          setState(() {
            _overrides[key] = value;
          });
        },
      );
    } else if (defaultValue is int || defaultValue is double || defaultValue is String || 
               defaultValue is Color || defaultValue is Duration) {
      return ListTile(
        title: Text(key),
        subtitle: TextField(
          controller: _controllers[key],
          keyboardType: defaultValue is int || defaultValue is double
              ? const TextInputType.numberWithOptions(signed: true, decimal: true)
              : TextInputType.text,
          textInputAction: TextInputAction.done,
          onChanged: (value) {
            // Store the string value for now - actual parsing would happen on save
            _overrides[key] = value;
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Settings'),
        actions: [
          TextButton(
            onPressed: _saveAndRestart,
            child: const Text('SAVE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: devConfigForSettings.entries
            .map((entry) => _buildSettingWidget(entry.key, entry.value))
            .toList(),
      ),
    );
  }
}
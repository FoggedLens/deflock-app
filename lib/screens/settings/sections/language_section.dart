import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../../services/localization_service.dart';
import '../../../app_state.dart';
import '../../../state/settings_state.dart';

class LanguageSection extends StatefulWidget {
  const LanguageSection({super.key});

  @override
  State<LanguageSection> createState() => _LanguageSectionState();
}

class _LanguageSectionState extends State<LanguageSection> {
  String? _selectedLanguage;
  Map<String, String> _languageNames = {};

  @override
  void initState() {
    super.initState();
    _loadSelectedLanguage();
    _loadLanguageNames();
  }

  Future<void> _loadSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _selectedLanguage = prefs.getString('language_code');
    });
  }

  Future<void> _loadLanguageNames() async {
    final locService = LocalizationService.instance;
    final Map<String, String> names = {};

    for (String langCode in locService.availableLanguages) {
      names[langCode] = await locService.getLanguageDisplayName(langCode);
    }

    if (!mounted) return;
    setState(() {
      _languageNames = names;
    });
  }

  Future<void> _setLanguage(String? languageCode) async {
    await LocalizationService.instance.setLanguage(languageCode);
    setState(() {
      _selectedLanguage = languageCode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return AnimatedBuilder(
          animation: LocalizationService.instance,
          builder: (context, child) {
            final locService = LocalizationService.instance;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // Language section
                RadioGroup<String?>(
                  groupValue: _selectedLanguage,
                  onChanged: _setLanguage,
                  child: Column(
                    children: [
                      // System Default option
                      RadioListTile<String?>(
                        title: Text(locService.t('settings.systemDefault')),
                        value: null,
                      ),
                      // English always appears second (if available)
                      if (locService.availableLanguages.contains('en'))
                        RadioListTile<String?>(
                          title: Text(_languageNames['en'] ?? 'English'),
                          value: 'en',
                        ),
                      // Other language options (excluding English since it's already shown)
                      ...locService.availableLanguages
                          .where((langCode) => langCode != 'en')
                          .map((langCode) =>
                        RadioListTile<String?>(
                          title: Text(_languageNames[langCode] ?? langCode.toUpperCase()),
                          value: langCode,
                        ),
                      ),
                    ],
                  ),
                ),

                // Divider between language and units
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),

                // Distance Units section
                Text(
                  locService.t('settings.distanceUnit'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  locService.t('settings.distanceUnitSubtitle'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),

                RadioGroup<DistanceUnit>(
                  groupValue: appState.distanceUnit,
                  onChanged: (unit) {
                    if (unit != null) {
                      appState.setDistanceUnit(unit);
                    }
                  },
                  child: Column(
                    children: [
                      // Metric option
                      RadioListTile<DistanceUnit>(
                        title: Text(locService.t('units.metricDescription')),
                        value: DistanceUnit.metric,
                      ),

                      // Imperial option
                      RadioListTile<DistanceUnit>(
                        title: Text(locService.t('units.imperialDescription')),
                        value: DistanceUnit.imperial,
                      ),
                    ],
                  ),
                ),
              ],
              ),
            );
          },
        );
      },
    );
  }
}

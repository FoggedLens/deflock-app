import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/localization_service.dart';

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

  _loadSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLanguage = prefs.getString('language_code');
    });
  }

  _loadLanguageNames() async {
    final locService = LocalizationService.instance;
    final Map<String, String> names = {};
    
    for (String langCode in locService.availableLanguages) {
      names[langCode] = await locService.getLanguageDisplayName(langCode);
    }
    
    setState(() {
      _languageNames = names;
    });
  }

  _setLanguage(String? languageCode) async {
    await LocalizationService.instance.setLanguage(languageCode);
    setState(() {
      _selectedLanguage = languageCode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                locService.t('settings.language'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            // System Default option
            RadioListTile<String?>(
              title: Text(locService.t('settings.systemDefault')),
              value: null,
              groupValue: _selectedLanguage,
              onChanged: _setLanguage,
            ),
            // Dynamic language options
            ...locService.availableLanguages.map((langCode) => 
              RadioListTile<String>(
                title: Text(_languageNames[langCode] ?? langCode.toUpperCase()),
                value: langCode,
                groupValue: _selectedLanguage,
                onChanged: _setLanguage,
              ),
            ),
          ],
        );
      },
    );
  }
}
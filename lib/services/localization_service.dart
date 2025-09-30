import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalizationService extends ChangeNotifier {
  static LocalizationService? _instance;
  static LocalizationService get instance => _instance ??= LocalizationService._();
  
  LocalizationService._();

  String _currentLanguage = 'en';
  Map<String, dynamic> _strings = {};
  List<String> _availableLanguages = [];

  String get currentLanguage => _currentLanguage;
  List<String> get availableLanguages => _availableLanguages;

  Future<void> init() async {
    await _discoverAvailableLanguages();
    await _loadSavedLanguage();
    await _loadStrings();
  }

  Future<void> _discoverAvailableLanguages() async {
    _availableLanguages = [];
    
    try {
      // Get the asset manifest to find all localization files
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      
      // Find all .json files in lib/localizations/
      final localizationFiles = manifestMap.keys
          .where((String key) => key.startsWith('lib/localizations/') && key.endsWith('.json'))
          .toList();
      
      for (final filePath in localizationFiles) {
        // Extract language code from filename (e.g., 'lib/localizations/pt.json' -> 'pt')
        final fileName = filePath.split('/').last;
        final languageCode = fileName.substring(0, fileName.length - 5); // Remove '.json'
        
        try {
          // Try to load and parse the file to ensure it's valid
          final jsonString = await rootBundle.loadString(filePath);
          final parsedJson = json.decode(jsonString);
          
          // Basic validation - ensure it has the expected structure
          if (parsedJson is Map && parsedJson.containsKey('language')) {
            _availableLanguages.add(languageCode);
            debugPrint('Found localization: $languageCode');
          }
        } catch (e) {
          debugPrint('Failed to load localization file $filePath: $e');
        }
      }
    } catch (e) {
      debugPrint('Failed to read AssetManifest.json: $e');
      // If manifest reading fails, we'll have an empty list
      // The system will handle this gracefully by falling back to 'en' in _loadSavedLanguage
    }
    
    debugPrint('Available languages: $_availableLanguages');
  }

  Future<void> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString('language_code');
    
    if (savedLanguage != null && _availableLanguages.contains(savedLanguage)) {
      _currentLanguage = savedLanguage;
    } else {
      // Use system default or fallback to English
      final systemLocale = Platform.localeName.split('_')[0];
      if (_availableLanguages.contains(systemLocale)) {
        _currentLanguage = systemLocale;
      } else {
        _currentLanguage = 'en';
      }
    }
  }

  Future<void> _loadStrings() async {
    try {
      final String jsonString = await rootBundle.loadString('lib/localizations/$_currentLanguage.json');
      _strings = json.decode(jsonString);
    } catch (e) {
      // Fallback to English if the language file doesn't exist
      if (_currentLanguage != 'en') {
        try {
          final String fallbackString = await rootBundle.loadString('lib/localizations/en.json');
          _strings = json.decode(fallbackString);
        } catch (e) {
          debugPrint('Failed to load fallback language file: $e');
          _strings = {};
        }
      } else {
        debugPrint('Failed to load language file for $_currentLanguage: $e');
        _strings = {};
      }
    }
  }

  Future<void> setLanguage(String? languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (languageCode == null) {
      // System default
      await prefs.remove('language_code');
      final systemLocale = Platform.localeName.split('_')[0];
      _currentLanguage = _availableLanguages.contains(systemLocale) ? systemLocale : 'en';
    } else {
      await prefs.setString('language_code', languageCode);
      _currentLanguage = languageCode;
    }
    
    await _loadStrings();
    notifyListeners();
  }

  String t(String key, {List<String>? params}) {
    List<String> keys = key.split('.');
    dynamic current = _strings;
    
    for (String k in keys) {
      if (current is Map && current.containsKey(k)) {
        current = current[k];
      } else {
        // Return the key as fallback for missing translations
        return key;
      }
    }
    
    String result = current is String ? current : key;
    
    // Replace parameters if provided - replace first occurrence only for each parameter
    if (params != null) {
      for (int i = 0; i < params.length; i++) {
        result = result.replaceFirst('{}', params[i]);
      }
    }
    
    return result;
  }

  // Get display name for a specific language code
  Future<String> getLanguageDisplayName(String languageCode) async {
    try {
      final String jsonString = await rootBundle.loadString('lib/localizations/$languageCode.json');
      final Map<String, dynamic> langData = json.decode(jsonString);
      return langData['language']?['name'] ?? languageCode.toUpperCase();
    } catch (e) {
      return languageCode.toUpperCase(); // Fallback to language code
    }
  }

  // Helper methods for common strings
  String get appTitle => t('app.title');
  String get settings => t('actions.settings');
  String get tagNode => t('actions.tagNode');
  String get download => t('actions.download');
  String get edit => t('actions.edit');
  String get cancel => t('actions.cancel');
  String get ok => t('actions.ok');
}
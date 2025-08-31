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
    // For now, we'll hardcode the languages we support
    // In the future, this could scan the assets directory
    _availableLanguages = ['en', 'es', 'fr', 'de'];
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

  String t(String key) {
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
    
    return current is String ? current : key;
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
#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

const String localizationsDir = 'lib/localizations';
const String referenceFile = 'en.json';

void main() async {
  print('🌍 Validating localization files...\n');
  
  try {
    final result = await validateLocalizations();
    if (result) {
      print('✅ All localization files are valid!');
      exit(0);
    } else {
      print('❌ Localization validation failed!');
      exit(1);
    }
  } catch (e) {
    print('💥 Error during validation: $e');
    exit(1);
  }
}

Future<bool> validateLocalizations() async {
  // Get all JSON files in localizations directory
  final locDir = Directory(localizationsDir);
  if (!locDir.existsSync()) {
    print('❌ Localizations directory not found: $localizationsDir');
    return false;
  }
  
  final jsonFiles = locDir
      .listSync()
      .where((file) => file.path.endsWith('.json'))
      .map((file) => file.path.split('/').last)
      .toList();
  
  if (jsonFiles.isEmpty) {
    print('❌ No JSON localization files found');
    return false;
  }
  
  print('📁 Found ${jsonFiles.length} localization files:');
  for (final file in jsonFiles) {
    print('   • $file');
  }
  print('');
  
  // Load reference file (English)
  final refFile = File('$localizationsDir/$referenceFile');
  if (!refFile.existsSync()) {
    print('❌ Reference file not found: $referenceFile');
    return false;
  }
  
  Map<String, dynamic> referenceData;
  try {
    final refContent = await refFile.readAsString();
    referenceData = json.decode(refContent) as Map<String, dynamic>;
  } catch (e) {
    print('❌ Failed to parse reference file $referenceFile: $e');
    return false;
  }
  
  final referenceKeys = _extractAllKeys(referenceData);
  print('🔑 Reference file ($referenceFile) has ${referenceKeys.length} keys');
  
  bool allValid = true;
  
  // Validate each localization file
  for (final fileName in jsonFiles) {
    if (fileName == referenceFile) continue; // Skip reference file
    
    print('\n🔍 Validating $fileName...');
    
    final file = File('$localizationsDir/$fileName');
    Map<String, dynamic> fileData;
    
    try {
      final content = await file.readAsString();
      fileData = json.decode(content) as Map<String, dynamic>;
    } catch (e) {
      print('   ❌ Failed to parse $fileName: $e');
      allValid = false;
      continue;
    }
    
    final fileKeys = _extractAllKeys(fileData);
    final validation = _validateKeys(referenceKeys, fileKeys, fileName);
    
    if (validation.isValid) {
      print('   ✅ Structure matches reference (${fileKeys.length} keys)');
    } else {
      print('   ❌ Structure validation failed:');
      for (final error in validation.errors) {
        print('      • $error');
      }
      allValid = false;
    }
  }
  
  return allValid;
}

/// Extract all nested keys from a JSON object using dot notation
/// Example: {"user": {"name": "John"}} -> ["user.name"]
Set<String> _extractAllKeys(Map<String, dynamic> data, {String prefix = ''}) {
  final keys = <String>{};
  
  for (final entry in data.entries) {
    final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    
    if (entry.value is Map<String, dynamic>) {
      // Recurse into nested objects
      keys.addAll(_extractAllKeys(entry.value as Map<String, dynamic>, prefix: key));
    } else {
      // Add leaf key
      keys.add(key);
    }
  }
  
  return keys;
}

class ValidationResult {
  final bool isValid;
  final List<String> errors;
  
  ValidationResult({required this.isValid, required this.errors});
}

ValidationResult _validateKeys(Set<String> referenceKeys, Set<String> fileKeys, String fileName) {
  final errors = <String>[];
  
  // Find missing keys
  final missingKeys = referenceKeys.difference(fileKeys);
  if (missingKeys.isNotEmpty) {
    errors.add('Missing ${missingKeys.length} keys: ${missingKeys.take(5).join(', ')}${missingKeys.length > 5 ? '...' : ''}');
  }
  
  // Find extra keys
  final extraKeys = fileKeys.difference(referenceKeys);
  if (extraKeys.isNotEmpty) {
    errors.add('Extra ${extraKeys.length} keys not in reference: ${extraKeys.take(5).join(', ')}${extraKeys.length > 5 ? '...' : ''}');
  }
  
  return ValidationResult(
    isValid: errors.isEmpty,
    errors: errors,
  );
}
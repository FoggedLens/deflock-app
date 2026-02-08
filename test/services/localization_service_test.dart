import 'dart:convert';
import 'dart:io';

import 'package:deflockapp/services/localization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String localizationsDir = 'lib/localizations';

/// Recursively extract all dot-notation leaf keys from a JSON map.
Set<String> extractLeafKeys(Map<String, dynamic> data, {String prefix = ''}) {
  final keys = <String>{};
  for (final entry in data.entries) {
    final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    if (entry.value is Map<String, dynamic>) {
      keys.addAll(
        extractLeafKeys(entry.value as Map<String, dynamic>, prefix: key),
      );
    } else {
      keys.add(key);
    }
  }
  return keys;
}

void main() {
  // ── Group 1: Localization file integrity ──────────────────────────────

  group('Localization file integrity', () {
    late Directory locDir;
    late List<File> jsonFiles;

    setUpAll(() {
      locDir = Directory(localizationsDir);
      if (locDir.existsSync()) {
        jsonFiles = locDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList();
      } else {
        jsonFiles = <File>[];
      }
    });

    test('localization directory exists and contains JSON files', () {
      expect(locDir.existsSync(), isTrue);
      expect(jsonFiles, isNotEmpty);
    });

    test('en.json exists (required fallback language)', () {
      final enFile = File('$localizationsDir/en.json');
      expect(enFile.existsSync(), isTrue);
    });

    test('every JSON file is valid JSON with a language.name key', () {
      for (final file in jsonFiles) {
        final name = p.basename(file.path);
        final content = file.readAsStringSync();
        final Map<String, dynamic> data;
        try {
          data = json.decode(content) as Map<String, dynamic>;
        } catch (e) {
          fail('$name is not valid JSON: $e');
          return; // unreachable, keeps analyzer happy
        }
        expect(
          data['language'],
          isA<Map>(),
          reason: '$name missing "language" object',
        );
        expect(
          (data['language'] as Map)['name'],
          isA<String>(),
          reason: '$name missing "language.name" string',
        );
      }
    });

    test('file names are valid 2-3 letter language codes', () {
      final codePattern = RegExp(r'^[a-z]{2,3}$');
      for (final file in jsonFiles) {
        final code = p.basenameWithoutExtension(file.path);
        expect(
          codePattern.hasMatch(code),
          isTrue,
          reason: '"$code" is not a valid 2-3 letter language code',
        );
      }
    });

    test('every locale file has exactly the same keys as en.json', () {
      final enData = json.decode(
        File('$localizationsDir/en.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final referenceKeys = extractLeafKeys(enData);

      for (final file in jsonFiles) {
        final name = p.basename(file.path);
        if (name == 'en.json') continue;

        final data = json.decode(file.readAsStringSync())
            as Map<String, dynamic>;
        final fileKeys = extractLeafKeys(data);

        final missing = referenceKeys.difference(fileKeys);
        final extra = fileKeys.difference(referenceKeys);

        expect(
          missing,
          isEmpty,
          reason: '$name is missing keys: $missing',
        );
        expect(
          extra,
          isEmpty,
          reason: '$name has extra keys not in en.json: $extra',
        );
      }
    });
  });

  // ── Group 2: t() translation lookup ───────────────────────────────────

  group('t() translation lookup', () {
    late Map<String, dynamic> enData;

    setUpAll(() {
      enData = json.decode(
        File('$localizationsDir/en.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    });

    test('simple nested key lookup', () {
      expect(
        LocalizationService.lookup(enData, 'app.title'),
        equals('DeFlock'),
      );
    });

    test('deeper nested key lookup', () {
      expect(
        LocalizationService.lookup(enData, 'actions.cancel'),
        equals('Cancel'),
      );
    });

    test('missing key returns the key string as fallback', () {
      expect(
        LocalizationService.lookup(enData, 'this.key.does.not.exist'),
        equals('this.key.does.not.exist'),
      );
    });

    test('single {} parameter substitution', () {
      expect(
        LocalizationService.lookup(enData, 'node.title', params: ['42']),
        equals('Node #42'),
      );
    });

    test('multiple {} parameter substitution', () {
      expect(
        LocalizationService.lookup(enData, 'proximityAlerts.rangeInfo',
            params: ['50', '500', 'm', '200']),
        equals('Range: 50-500 m (default: 200)'),
      );
    });

    test('partial path resolving to a Map returns the key as fallback', () {
      expect(
        LocalizationService.lookup(enData, 'actions'),
        equals('actions'),
      );
    });
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deflockapp/models/service_registry_entry.dart';
import 'package:deflockapp/state/service_registry.dart';

/// Simple test entry implementing ServiceRegistryEntry.
class TestEntry implements ServiceRegistryEntry {
  @override
  final String id;
  @override
  final String name;
  @override
  final bool enabled;
  @override
  final bool isBuiltIn;

  const TestEntry({
    required this.id,
    required this.name,
    this.enabled = true,
    this.isBuiltIn = false,
  });

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'isBuiltIn': isBuiltIn,
  };

  static TestEntry fromJson(Map<String, dynamic> json) => TestEntry(
    id: json['id'] as String,
    name: json['name'] as String,
    enabled: json['enabled'] as bool? ?? true,
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
  );

  TestEntry copyWith({bool? enabled}) => TestEntry(
    id: id,
    name: name,
    enabled: enabled ?? this.enabled,
    isBuiltIn: isBuiltIn,
  );
}

List<TestEntry> _createDefaults() => const [
  TestEntry(id: 'default-1', name: 'Default One', isBuiltIn: true),
  TestEntry(id: 'default-2', name: 'Default Two', isBuiltIn: true),
];

void main() {
  late ServiceRegistry<TestEntry> registry;
  late int changeCount;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    changeCount = 0;
    registry = ServiceRegistry(
      prefsKey: 'test_entries',
      fromJson: TestEntry.fromJson,
      createDefaults: _createDefaults,
      onChanged: () => changeCount++,
    );
  });

  group('load', () {
    test('fresh install creates and persists defaults', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(registry.entries, hasLength(2));
      expect(registry.entries[0].id, 'default-1');
      expect(registry.entries[1].id, 'default-2');

      // Verify persisted
      expect(prefs.containsKey('test_entries'), isTrue);
    });

    test('existing valid JSON loads entries', () async {
      final existing = [
        const TestEntry(id: 'custom', name: 'Custom'),
        const TestEntry(id: 'default-1', name: 'D1', isBuiltIn: true),
        const TestEntry(id: 'default-2', name: 'D2', isBuiltIn: true),
      ];
      SharedPreferences.setMockInitialValues({
        'test_entries': jsonEncode(existing.map((e) => e.toJson()).toList()),
      });

      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(registry.entries, hasLength(3));
      expect(registry.entries[0].id, 'custom');
    });

    test('corrupted JSON falls back to defaults', () async {
      SharedPreferences.setMockInitialValues({
        'test_entries': 'not valid json!!!',
      });

      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(registry.entries, hasLength(2));
      expect(registry.entries[0].id, 'default-1');
    });

    test('adds missing built-in entries to existing list', () async {
      final existing = [
        const TestEntry(id: 'custom', name: 'Custom'),
        const TestEntry(id: 'default-1', name: 'D1', isBuiltIn: true),
        // default-2 is missing
      ];
      SharedPreferences.setMockInitialValues({
        'test_entries': jsonEncode(existing.map((e) => e.toJson()).toList()),
      });

      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(registry.entries, hasLength(3));
      expect(registry.entries[2].id, 'default-2');
    });
  });

  group('addOrUpdate', () {
    test('new entry appended to end', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.addOrUpdate(
        const TestEntry(id: 'new-one', name: 'New One'),
      );

      expect(registry.entries, hasLength(3));
      expect(registry.entries.last.id, 'new-one');
      expect(changeCount, 1);
    });

    test('existing entry replaced in-place preserving position', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.addOrUpdate(
        const TestEntry(id: 'default-1', name: 'Updated Name', isBuiltIn: true),
      );

      expect(registry.entries, hasLength(2));
      expect(registry.entries[0].name, 'Updated Name');
      expect(changeCount, 1);
    });

    test('persists changes', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.addOrUpdate(
        const TestEntry(id: 'new-one', name: 'New'),
      );

      // Re-load from prefs to verify persistence
      final registry2 = ServiceRegistry<TestEntry>(
        prefsKey: 'test_entries',
        fromJson: TestEntry.fromJson,
        createDefaults: _createDefaults,
        onChanged: () {},
      );
      await registry2.load(prefs);
      expect(registry2.entries, hasLength(3));
      expect(registry2.entries.last.id, 'new-one');
    });
  });

  group('delete', () {
    test('removes entry and persists', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      // Add a custom entry first so we have 3
      await registry.addOrUpdate(
        const TestEntry(id: 'custom', name: 'Custom'),
      );
      changeCount = 0;

      await registry.delete('custom');

      expect(registry.entries, hasLength(2));
      expect(registry.findById('custom'), isNull);
      expect(changeCount, 1);
    });

    test('throws StateError on last entry', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      // Remove one default so only one remains
      await registry.delete('default-2');

      await expectLater(
        () => registry.delete('default-1'),
        throwsA(isA<StateError>()),
      );
    });

    test('no-op for nonexistent id', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.delete('nonexistent');
      expect(registry.entries, hasLength(2));
      expect(changeCount, 0);
    });
  });

  group('reorder', () {
    test('moves entry from first to last', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.addOrUpdate(
        const TestEntry(id: 'third', name: 'Third'),
      );
      changeCount = 0;

      await registry.reorder(0, 3); // Move index 0 to after index 2

      expect(registry.entries[0].id, 'default-2');
      expect(registry.entries[1].id, 'third');
      expect(registry.entries[2].id, 'default-1');
      expect(changeCount, 1);
    });

    test('same index is no-op', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.reorder(0, 0);

      expect(changeCount, 0);
    });

    test('persists new order', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.reorder(0, 2);

      // Re-load
      final registry2 = ServiceRegistry<TestEntry>(
        prefsKey: 'test_entries',
        fromJson: TestEntry.fromJson,
        createDefaults: _createDefaults,
        onChanged: () {},
      );
      await registry2.load(prefs);
      expect(registry2.entries[0].id, 'default-2');
      expect(registry2.entries[1].id, 'default-1');
    });
  });

  group('resetToDefaults', () {
    test('replaces all entries with defaults', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.addOrUpdate(
        const TestEntry(id: 'custom', name: 'Custom'),
      );
      changeCount = 0;

      await registry.resetToDefaults();

      expect(registry.entries, hasLength(2));
      expect(registry.entries[0].id, 'default-1');
      expect(changeCount, 1);
    });

    test('custom entries removed', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      await registry.addOrUpdate(
        const TestEntry(id: 'custom-1', name: 'C1'),
      );
      await registry.addOrUpdate(
        const TestEntry(id: 'custom-2', name: 'C2'),
      );

      await registry.resetToDefaults();

      expect(registry.findById('custom-1'), isNull);
      expect(registry.findById('custom-2'), isNull);
    });
  });

  group('enabledEntries', () {
    test('filters disabled entries', () async {
      // Include the defaults (which load will check for) plus custom entries
      final existing = [
        const TestEntry(id: 'default-1', name: 'D1', enabled: true, isBuiltIn: true),
        const TestEntry(id: 'default-2', name: 'D2', enabled: false, isBuiltIn: true),
        const TestEntry(id: 'c', name: 'C', enabled: true),
      ];
      SharedPreferences.setMockInitialValues({
        'test_entries': jsonEncode(existing.map((e) => e.toJson()).toList()),
      });

      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      final enabled = registry.enabledEntries;
      expect(enabled, hasLength(2));
      expect(enabled[0].id, 'default-1');
      expect(enabled[1].id, 'c');
    });

    test('returns empty list when all disabled', () async {
      final existing = [
        const TestEntry(id: 'default-1', name: 'D1', enabled: false, isBuiltIn: true),
        const TestEntry(id: 'default-2', name: 'D2', enabled: false, isBuiltIn: true),
      ];
      SharedPreferences.setMockInitialValues({
        'test_entries': jsonEncode(existing.map((e) => e.toJson()).toList()),
      });

      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(registry.enabledEntries, isEmpty);
    });
  });

  group('findById', () {
    test('returns entry when found', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(registry.findById('default-1')?.name, 'Default One');
    });

    test('returns null when not found', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(registry.findById('nonexistent'), isNull);
    });
  });

  group('entries list immutability', () {
    test('entries returns unmodifiable list', () async {
      final prefs = await SharedPreferences.getInstance();
      await registry.load(prefs);

      expect(
        () => registry.entries.add(const TestEntry(id: 'x', name: 'X')),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

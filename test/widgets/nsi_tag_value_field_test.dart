import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the tag value field clearing bug and fix.
///
/// Root cause: RawAutocomplete.onFieldSubmitted auto-selects the first option
/// when called, and NSITagValueField's optionsBuilder returns ALL suggestions
/// when the text is empty. So pressing "Done" on the keyboard with an empty
/// field auto-selects the first NSI suggestion, making the value "pop back in".
void main() {
  // Helper to build a RawAutocomplete widget tree that mirrors NSITagValueField
  Widget buildAutocompleteField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required List<String> suggestions,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSelected,
    required bool guardOnSubmitted,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: RawAutocomplete<String>(
            textEditingController: controller,
            focusNode: focusNode,
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (suggestions.isEmpty) {
                return const Iterable<String>.empty();
              }
              if (textEditingValue.text.isEmpty) return suggestions;
              return suggestions
                  .where((s) => s.contains(textEditingValue.text));
            },
            onSelected: (String selection) => onSelected(selection),
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: guardOnSubmitted
                    ? (_) {
                        if (controller.text.isNotEmpty) {
                          onFieldSubmitted();
                        }
                      }
                    : (_) => onFieldSubmitted(),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  child: SizedBox(
                    height: 200,
                    child: ListView(
                      children: options
                          .map((o) => ListTile(
                                title: Text(o),
                                onTap: () => onSelected(o),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  group('NSITagValueField onSubmitted behavior', () {
    testWidgets(
        'unguarded onFieldSubmitted auto-selects first suggestion on empty submit',
        (tester) async {
      String reportedValue = 'Hikvision';
      final controller = TextEditingController(text: 'Hikvision');
      final focusNode = FocusNode();

      await tester.pumpWidget(buildAutocompleteField(
        controller: controller,
        focusNode: focusNode,
        suggestions: ['Axis', 'Dahua', 'Hikvision'],
        onChanged: (v) => reportedValue = v,
        onSelected: (v) => reportedValue = v,
        guardOnSubmitted: false, // old behavior
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Clear the field
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(controller.text, equals(''));

      // Press "Done" on the keyboard
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Demonstrates the bug: first suggestion ('Axis') is auto-selected
      expect(controller.text, equals('Axis'),
          reason: 'Unguarded onFieldSubmitted auto-selects first suggestion');
    });

    testWidgets(
        'guarded onFieldSubmitted keeps field empty on submit',
        (tester) async {
      String reportedValue = 'Hikvision';
      final controller = TextEditingController(text: 'Hikvision');
      final focusNode = FocusNode();

      await tester.pumpWidget(buildAutocompleteField(
        controller: controller,
        focusNode: focusNode,
        suggestions: ['Axis', 'Dahua', 'Hikvision'],
        onChanged: (v) => reportedValue = v,
        onSelected: (v) => reportedValue = v,
        guardOnSubmitted: true, // fixed behavior
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Clear the field
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(controller.text, equals(''));
      expect(reportedValue, equals(''));

      // Press "Done" on the keyboard
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Field stays empty
      expect(controller.text, equals(''),
          reason: 'Field should stay empty after pressing Done');
      expect(reportedValue, equals(''),
          reason: 'Parent should not receive a new value');
    });

    testWidgets(
        'guarded onFieldSubmitted still auto-completes when text is present',
        (tester) async {
      String reportedValue = '';
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(buildAutocompleteField(
        controller: controller,
        focusNode: focusNode,
        suggestions: ['Axis', 'Dahua', 'Hikvision'],
        onChanged: (v) => reportedValue = v,
        onSelected: (v) => reportedValue = v,
        guardOnSubmitted: true, // fixed behavior
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      // Type a partial match
      await tester.enterText(find.byType(TextField), 'Axi');
      await tester.pump();

      // Press "Done" → should auto-complete to 'Axis'
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(controller.text, equals('Axis'),
          reason: 'Should auto-complete partial text to first matching suggestion');
      expect(reportedValue, equals('Axis'));
    });
  });
}

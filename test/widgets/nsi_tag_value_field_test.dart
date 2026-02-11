import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the RawAutocomplete onSubmitted behavior used by NSITagValueField.
///
/// These test the exact widget tree pattern from NSITagValueField.build():
/// - onFieldSubmitted guarded on non-empty text (prevents auto-select on Done)
/// - onCleared callback fires when Done is pressed on an empty field
void main() {
  Widget buildAutocompleteField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required List<String> suggestions,
    required ValueChanged<String> onChanged,
    required ValueChanged<String> onSelected,
    VoidCallback? onCleared,
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
                onSubmitted: (_) {
                  if (controller.text.isNotEmpty) {
                    onFieldSubmitted();
                  } else {
                    onCleared?.call();
                  }
                },
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
    testWidgets('pressing Done on empty field does not auto-select',
        (tester) async {
      final controller = TextEditingController(text: 'Hikvision');
      final focusNode = FocusNode();

      await tester.pumpWidget(buildAutocompleteField(
        controller: controller,
        focusNode: focusNode,
        suggestions: ['Axis', 'Dahua', 'Hikvision'],
        onChanged: (_) {},
        onSelected: (_) {},
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(controller.text, equals(''),
          reason: 'Field should stay empty after pressing Done');
    });

    testWidgets('pressing Done on empty field calls onCleared',
        (tester) async {
      bool clearedCalled = false;
      final controller = TextEditingController(text: 'Hikvision');
      final focusNode = FocusNode();

      await tester.pumpWidget(buildAutocompleteField(
        controller: controller,
        focusNode: focusNode,
        suggestions: ['Axis', 'Dahua', 'Hikvision'],
        onChanged: (_) {},
        onSelected: (_) {},
        onCleared: () => clearedCalled = true,
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(clearedCalled, isTrue,
          reason: 'onCleared should fire when Done pressed on empty field');
    });

    testWidgets('pressing Done on non-empty field does not call onCleared',
        (tester) async {
      bool clearedCalled = false;
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(buildAutocompleteField(
        controller: controller,
        focusNode: focusNode,
        suggestions: ['Axis', 'Dahua', 'Hikvision'],
        onChanged: (_) {},
        onSelected: (_) {},
        onCleared: () => clearedCalled = true,
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Axi');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(clearedCalled, isFalse,
          reason: 'onCleared should not fire when field has text');
      expect(controller.text, equals('Axis'),
          reason: 'Should auto-complete partial text');
    });

    testWidgets('onCleared not provided — Done on empty field is a no-op',
        (tester) async {
      final controller = TextEditingController(text: 'Dahua');
      final focusNode = FocusNode();
      String lastSelected = '';

      await tester.pumpWidget(buildAutocompleteField(
        controller: controller,
        focusNode: focusNode,
        suggestions: ['Axis', 'Dahua', 'Hikvision'],
        onChanged: (_) {},
        onSelected: (v) => lastSelected = v,
        // onCleared intentionally omitted
      ));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(controller.text, equals(''));
      expect(lastSelected, equals(''),
          reason: 'No selection should occur on empty submit');
    });
  });
}

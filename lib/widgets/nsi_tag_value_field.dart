import 'package:flutter/material.dart';

import '../services/nsi_service.dart';

/// A text field that provides NSI suggestions for OSM tag values
class NSITagValueField extends StatefulWidget {
  const NSITagValueField({
    super.key,
    required this.tagKey,
    required this.initialValue,
    required this.onChanged,
    this.readOnly = false,
    this.hintText,
  });

  final String tagKey;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final bool readOnly;
  final String? hintText;

  @override
  State<NSITagValueField> createState() => _NSITagValueFieldState();
}

class _NSITagValueFieldState extends State<NSITagValueField> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _loadSuggestions();
  }

  @override
  void didUpdateWidget(NSITagValueField oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If the tag key changed, reload suggestions
    if (oldWidget.tagKey != widget.tagKey) {
      _suggestions.clear();
      _loadSuggestions();
    }

    // If the initial value changed, update the controller
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadSuggestions() async {
    if (widget.tagKey.trim().isEmpty) return;

    try {
      final suggestions = await NSIService().getAllSuggestions(widget.tagKey);
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
        });
      }
    } catch (e) {
      // Silently fail - field still works as regular text field
      if (mounted) {
        setState(() {
          _suggestions = [];
        });
      }
    }
  }

  InputDecoration _buildDecoration({required bool showDropdownIcon}) {
    return InputDecoration(
      hintText: widget.hintText,
      border: const OutlineInputBorder(),
      isDense: true,
      suffixIcon: showDropdownIcon
          ? Icon(
              Icons.arrow_drop_down,
              color: _focusNode.hasFocus
                  ? Theme.of(context).primaryColor
                  : Colors.grey,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return TextField(
        controller: _controller,
        focusNode: _focusNode,
        readOnly: true,
        decoration: _buildDecoration(showDropdownIcon: false),
      );
    }

    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (_suggestions.isEmpty) return const Iterable<String>.empty();
        if (textEditingValue.text.isEmpty) {
          return _suggestions.take(10);
        }
        return _suggestions
            .where((s) => s.contains(textEditingValue.text))
            .take(10);
      },
      onSelected: (String selection) {
        widget.onChanged(selection);
      },
      fieldViewBuilder: (
        BuildContext context,
        TextEditingController controller,
        FocusNode focusNode,
        VoidCallback onFieldSubmitted,
      ) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: _buildDecoration(
            showDropdownIcon: _suggestions.isNotEmpty,
          ),
          onChanged: (value) {
            widget.onChanged(value);
          },
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (
        BuildContext context,
        AutocompleteOnSelected<String> onSelected,
        Iterable<String> options,
      ) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option, style: const TextStyle(fontSize: 14)),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

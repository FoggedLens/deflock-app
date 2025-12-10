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
  List<String> _suggestions = [];
  bool _showingSuggestions = false;
  final LayerLink _layerLink = LayerLink();
  late OverlayEntry _overlayEntry;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _loadSuggestions();
    
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(NSITagValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If the tag key changed, reload suggestions
    if (oldWidget.tagKey != widget.tagKey) {
      _hideSuggestions(); // Hide old suggestions immediately
      _suggestions.clear();
      _loadSuggestions(); // Load new suggestions for new key
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
    _hideSuggestions();
    super.dispose();
  }

  void _loadSuggestions() async {
    if (widget.tagKey.trim().isEmpty) return;
    
    try {
      final suggestions = await NSIService().getAllSuggestions(widget.tagKey);
      if (mounted) {
        setState(() {
          _suggestions = suggestions.take(10).toList(); // Limit to 10 suggestions
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

  void _onFocusChanged() {
    if (_focusNode.hasFocus && _suggestions.isNotEmpty && !widget.readOnly) {
      _showSuggestions();
    } else {
      _hideSuggestions();
    }
  }

  void _showSuggestions() {
    if (_showingSuggestions || _suggestions.isEmpty) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 200, // Fixed width for suggestions
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0.0, 35.0), // Below the text field
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _suggestions[index];
                  return ListTile(
                    dense: true,
                    title: Text(suggestion, style: const TextStyle(fontSize: 14)),
                    onTap: () => _selectSuggestion(suggestion),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry);
    setState(() {
      _showingSuggestions = true;
    });
  }

  void _hideSuggestions() {
    if (!_showingSuggestions) return;

    _overlayEntry.remove();
    setState(() {
      _showingSuggestions = false;
    });
  }

  void _selectSuggestion(String suggestion) {
    _controller.text = suggestion;
    widget.onChanged(suggestion);
    _hideSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        readOnly: widget.readOnly,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _suggestions.isNotEmpty && !widget.readOnly
              ? Icon(
                  Icons.arrow_drop_down,
                  color: _showingSuggestions ? Theme.of(context).primaryColor : Colors.grey,
                )
              : null,
        ),
        onChanged: widget.readOnly ? null : (value) {
          widget.onChanged(value);
        },
        onTap: () {
          if (!widget.readOnly && _suggestions.isNotEmpty) {
            _showSuggestions();
          }
        },
      ),
    );
  }
}
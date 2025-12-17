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
    _controller.addListener(_onTextChanged);
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

  /// Get filtered suggestions based on current text input (case-sensitive)
  List<String> _getFilteredSuggestions() {
    final currentText = _controller.text;
    if (currentText.isEmpty) {
      return _suggestions;
    }
    
    return _suggestions
        .where((suggestion) => suggestion.contains(currentText))
        .toList();
  }

  /// Handle text changes to update suggestion filtering
  void _onTextChanged() {
    if (_showingSuggestions) {
      // Update the overlay with filtered suggestions
      _updateSuggestionsOverlay();
    }
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
    final filteredSuggestions = _getFilteredSuggestions();
    if (_focusNode.hasFocus && filteredSuggestions.isNotEmpty && !widget.readOnly) {
      _showSuggestions();
    } else {
      _hideSuggestions();
    }
  }

  void _showSuggestions() {
    final filteredSuggestions = _getFilteredSuggestions();
    if (_showingSuggestions || filteredSuggestions.isEmpty) return;

    _overlayEntry = _buildSuggestionsOverlay(filteredSuggestions);
    Overlay.of(context).insert(_overlayEntry);
    setState(() {
      _showingSuggestions = true;
    });
  }

  /// Update the suggestions overlay with current filtered suggestions
  void _updateSuggestionsOverlay() {
    final filteredSuggestions = _getFilteredSuggestions();
    
    if (filteredSuggestions.isEmpty) {
      _hideSuggestions();
      return;
    }
    
    if (_showingSuggestions) {
      // Remove current overlay and create new one with filtered suggestions
      _overlayEntry.remove();
      _overlayEntry = _buildSuggestionsOverlay(filteredSuggestions);
      Overlay.of(context).insert(_overlayEntry);
    }
  }

  /// Build the suggestions overlay with the given suggestions list
  OverlayEntry _buildSuggestionsOverlay(List<String> suggestions) {
    return OverlayEntry(
      builder: (context) => Positioned(
        width: 250, // Slightly wider to fit more content in refine tags
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
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
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
    final filteredSuggestions = _getFilteredSuggestions();
    
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
          if (!widget.readOnly && filteredSuggestions.isNotEmpty) {
            _showSuggestions();
          }
        },
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/search_result.dart';
import '../services/localization_service.dart';
import '../widgets/debouncer.dart';

class LocationSearchBar extends StatefulWidget {
  final void Function(SearchResult)? onResultSelected;
  final VoidCallback? onCancel;
  
  const LocationSearchBar({
    super.key,
    this.onResultSelected,
    this.onCancel,
  });

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final Debouncer _searchDebouncer = Debouncer(const Duration(milliseconds: 500));
  
  bool _showResults = false;
  
  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }
  
  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _searchDebouncer.dispose();
    super.dispose();
  }
  
  void _onFocusChanged() {
    setState(() {
      _showResults = _focusNode.hasFocus && _controller.text.isNotEmpty;
    });
  }
  
  void _onSearchChanged(String query) {
    setState(() {
      _showResults = query.isNotEmpty && _focusNode.hasFocus;
    });
    
    if (query.isEmpty) {
      // Clear navigation search results instead of old search state
      final appState = context.read<AppState>();
      appState.clearNavigationSearchResults();
      return;
    }
    
    // Debounce search to avoid too many API calls
    _searchDebouncer(() {
      if (mounted) {
        final appState = context.read<AppState>();
        appState.searchNavigation(query);
      }
    });
  }
  
  void _onResultTap(SearchResult result) {
    _controller.text = result.displayName;
    setState(() {
      _showResults = false;
    });
    _focusNode.unfocus();
    
    widget.onResultSelected?.call(result);
  }
  
  void _onClear() {
    _controller.clear();
    context.read<AppState>().clearNavigationSearchResults();
    setState(() {
      _showResults = false;
    });
  }
  
  void _onCancel() {
    _controller.clear();
    context.read<AppState>().clearNavigationSearchResults();
    setState(() {
      _showResults = false;
    });
    _focusNode.unfocus();
    widget.onCancel?.call();
  }
  
  Widget _buildResultsList(List<SearchResult> results, bool isLoading) {
    if (!_showResults) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(LocalizationService.instance.t('navigation.searching')),
                ],
              ),
            )
          else if (results.isEmpty && _controller.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(LocalizationService.instance.t('navigation.noResultsFound')),
            )
          else
            ...results.map((result) => ListTile(
              leading: Icon(
                result.category == 'coordinates' ? Icons.place : Icons.location_on,
                size: 20,
              ),
              title: Text(
                result.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: result.type != null 
                  ? Text(result.type!, style: Theme.of(context).textTheme.bodySmall)
                  : null,
              dense: true,
              onTap: () => _onResultTap(result),
            )).toList(),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).shadowColor.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: LocalizationService.instance.t('navigation.searchPlaceholder'),
                  prefixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _onCancel,
                        tooltip: LocalizationService.instance.t('navigation.cancelSearch'),
                      ),
                      const Icon(Icons.search),
                    ],
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 80),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _onClear,
                          tooltip: LocalizationService.instance.t('actions.clear'),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            _buildResultsList(appState.navigationSearchResults, appState.isNavigationSearchLoading),
          ],
        );
      },
    );
  }
}
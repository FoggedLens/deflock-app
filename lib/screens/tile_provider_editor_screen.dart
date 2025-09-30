import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';

import '../app_state.dart';
import '../models/tile_provider.dart';
import '../services/localization_service.dart';
import '../dev_config.dart';

class TileProviderEditorScreen extends StatefulWidget {
  final TileProvider? provider; // null for adding new provider

  const TileProviderEditorScreen({super.key, this.provider});

  @override
  State<TileProviderEditorScreen> createState() => _TileProviderEditorScreenState();
}

class _TileProviderEditorScreenState extends State<TileProviderEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _apiKeyController;
  late List<TileType> _tileTypes;
  
  bool get _isEditing => widget.provider != null;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _nameController = TextEditingController(text: provider?.name ?? '');
    _apiKeyController = TextEditingController(text: provider?.apiKey ?? '');
    _tileTypes = provider != null 
        ? List.from(provider.tileTypes)
        : <TileType>[];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return Scaffold(
          appBar: AppBar(
            title: Text(_isEditing ? locService.t('tileProviders.editProvider') : locService.t('tileProviders.addProvider')),
            actions: [
              TextButton(
                onPressed: _saveProvider,
                child: Text(locService.t('tileTypeEditor.save')),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: locService.t('tileProviders.providerName'),
                    hintText: locService.t('tileProviders.providerNameHint'),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return locService.t('tileProviders.providerNameRequired');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apiKeyController,
                  decoration: InputDecoration(
                    labelText: locService.t('tileProviders.apiKey'),
                    hintText: locService.t('tileProviders.apiKeyHint'),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      locService.t('tileProviders.tileTypes'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    TextButton.icon(
                      onPressed: _addTileType,
                      icon: const Icon(Icons.add),
                      label: Text(locService.t('tileProviders.addType')),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_tileTypes.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(locService.t('tileProviders.noTileTypesConfigured')),
                    ),
                  )
                else
                  ..._tileTypes.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tileType = entry.value;
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(tileType.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tileType.urlTemplate),
                            Text(
                              tileType.attribution,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editTileType(index),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: _tileTypes.length > 1 
                                  ? () => _deleteTileType(index)
                                  : null, // Can't delete last tile type
                            ),
                          ],
                        ),
                        onTap: () => _editTileType(index),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _addTileType() {
    _showTileTypeDialog();
  }

  void _editTileType(int index) {
    _showTileTypeDialog(tileType: _tileTypes[index], index: index);
  }

  void _deleteTileType(int index) {
    if (_tileTypes.length <= 1) return;
    
    final tileTypeToDelete = _tileTypes[index];
    final appState = context.read<AppState>();
    
    setState(() {
      _tileTypes.removeAt(index);
    });
    
    // If we're deleting the currently selected tile type, switch to another one
    if (appState.selectedTileType?.id == tileTypeToDelete.id) {
      // Find first remaining tile type in this provider or any other provider
      TileType? replacement;
      if (_tileTypes.isNotEmpty) {
        replacement = _tileTypes.first;
      } else {
        // Look in other providers
        for (final provider in appState.tileProviders) {
          if (provider.availableTileTypes.isNotEmpty) {
            replacement = provider.availableTileTypes.first;
            break;
          }
        }
      }
      
      if (replacement != null) {
        appState.setSelectedTileType(replacement.id);
      }
    }
  }

  void _showTileTypeDialog({TileType? tileType, int? index}) {
    showDialog(
      context: context,
      builder: (context) => _TileTypeDialog(
        tileType: tileType,
        onSave: (newTileType) {
          setState(() {
            if (index != null) {
              _tileTypes[index] = newTileType;
            } else {
              _tileTypes.add(newTileType);
            }
          });
        },
      ),
    );
  }

  void _saveProvider() {
    final locService = LocalizationService.instance;
    if (!_formKey.currentState!.validate()) return;
    if (_tileTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(locService.t('tileProviders.atLeastOneTileTypeRequired'))),
      );
      return;
    }

    final providerId = widget.provider?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final provider = TileProvider(
      id: providerId,
      name: _nameController.text.trim(),
      apiKey: _apiKeyController.text.trim().isEmpty ? null : _apiKeyController.text.trim(),
      tileTypes: _tileTypes,
    );

    context.read<AppState>().addOrUpdateTileProvider(provider);
    Navigator.of(context).pop();
  }
}

class _TileTypeDialog extends StatefulWidget {
  final TileType? tileType;
  final Function(TileType) onSave;

  const _TileTypeDialog({
    required this.onSave,
    this.tileType,
  });

  @override
  State<_TileTypeDialog> createState() => _TileTypeDialogState();
}

class _TileTypeDialogState extends State<_TileTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _attributionController;
  Uint8List? _previewTile;
  bool _isLoadingPreview = false;

  @override
  void initState() {
    super.initState();
    final tileType = widget.tileType;
    _nameController = TextEditingController(text: tileType?.name ?? '');
    _urlController = TextEditingController(text: tileType?.urlTemplate ?? '');
    _attributionController = TextEditingController(text: tileType?.attribution ?? '');
    _previewTile = tileType?.previewTile;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _attributionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final locService = LocalizationService.instance;
        
        return AlertDialog(
          title: Text(widget.tileType != null ? locService.t('tileTypeEditor.editTileType') : locService.t('tileTypeEditor.addTileType')),
          content: SizedBox(
            width: double.maxFinite,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: locService.t('tileTypeEditor.name'),
                      hintText: locService.t('tileTypeEditor.nameHint'),
                    ),
                    validator: (value) => value?.trim().isEmpty == true ? locService.t('tileTypeEditor.nameRequired') : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: locService.t('tileTypeEditor.urlTemplate'),
                      hintText: locService.t('tileTypeEditor.urlTemplateHint'),
                    ),
                    validator: (value) {
                      if (value?.trim().isEmpty == true) return locService.t('tileTypeEditor.urlTemplateRequired');
                      if (!value!.contains('{z}') || !value.contains('{x}') || !value.contains('{y}')) {
                        return locService.t('tileTypeEditor.urlTemplatePlaceholders');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _attributionController,
                    decoration: InputDecoration(
                      labelText: locService.t('tileTypeEditor.attribution'),
                      hintText: locService.t('tileTypeEditor.attributionHint'),
                    ),
                    validator: (value) => value?.trim().isEmpty == true ? locService.t('tileTypeEditor.attributionRequired') : null,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: _isLoadingPreview ? null : _fetchPreviewTile,
                        icon: _isLoadingPreview 
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.preview),
                        label: Text(locService.t('tileTypeEditor.fetchPreview')),
                      ),
                      const SizedBox(width: 8),
                      if (_previewTile != null)
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                          ),
                          child: Image.memory(_previewTile!, fit: BoxFit.cover),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(locService.cancel),
            ),
            TextButton(
              onPressed: _saveTileType,
              child: Text(locService.t('tileTypeEditor.save')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchPreviewTile() async {
    final locService = LocalizationService.instance;
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoadingPreview = true;
    });

    try {
      // Use a sample tile from configured preview location
      final url = _urlController.text
          .replaceAll('{z}', kPreviewTileZoom.toString())
          .replaceAll('{x}', kPreviewTileX.toString())
          .replaceAll('{y}', kPreviewTileY.toString());
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        setState(() {
          _previewTile = response.bodyBytes;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locService.t('tileTypeEditor.previewTileLoaded'))),
          );
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(locService.t('tileTypeEditor.previewTileFailed', params: [e.toString()]))),
        );
      }
    } finally {
      setState(() {
        _isLoadingPreview = false;
      });
    }
  }

  void _saveTileType() {
    if (!_formKey.currentState!.validate()) return;

    final tileTypeId = widget.tileType?.id ?? 
        '${_nameController.text.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}';
    
    final tileType = TileType(
      id: tileTypeId,
      name: _nameController.text.trim(),
      urlTemplate: _urlController.text.trim(),
      attribution: _attributionController.text.trim(),
      previewTile: _previewTile,
    );

    widget.onSave(tileType);
    Navigator.of(context).pop();
  }
}
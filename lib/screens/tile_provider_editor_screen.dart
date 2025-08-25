import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:collection/collection.dart';

import '../app_state.dart';
import '../models/tile_provider.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Provider' : 'Add Provider'),
        actions: [
          TextButton(
            onPressed: _saveProvider,
            child: const Text('Save'),
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
              decoration: const InputDecoration(
                labelText: 'Provider Name',
                hintText: 'e.g., Custom Maps Inc.',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Provider name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key (Optional)',
                hintText: 'Enter API key if required by tile types',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tile Types',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                TextButton.icon(
                  onPressed: _addTileType,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Type'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_tileTypes.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No tile types configured'),
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
    if (!_formKey.currentState!.validate()) return;
    if (_tileTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one tile type is required')),
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
    return AlertDialog(
      title: Text(widget.tileType != null ? 'Edit Tile Type' : 'Add Tile Type'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g., Satellite',
                ),
                validator: (value) => value?.trim().isEmpty == true ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL Template',
                  hintText: 'https://example.com/{z}/{x}/{y}.png',
                ),
                validator: (value) {
                  if (value?.trim().isEmpty == true) return 'URL template is required';
                  if (!value!.contains('{z}') || !value.contains('{x}') || !value.contains('{y}')) {
                    return 'URL must contain {z}, {x}, and {y} placeholders';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _attributionController,
                decoration: const InputDecoration(
                  labelText: 'Attribution',
                  hintText: '© Map Provider',
                ),
                validator: (value) => value?.trim().isEmpty == true ? 'Attribution is required' : null,
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
                    label: const Text('Fetch Preview'),
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
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saveTileType,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _fetchPreviewTile() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoadingPreview = true;
    });

    try {
      // Use a sample tile (zoom 10, somewhere in the world)
      final url = _urlController.text
          .replaceAll('{z}', '10')
          .replaceAll('{x}', '512')
          .replaceAll('{y}', '384');
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        setState(() {
          _previewTile = response.bodyBytes;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Preview tile loaded successfully')),
          );
        }
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to fetch preview: $e')),
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
import 'package:flutter/foundation.dart';

import '../models/tile_provider.dart';
import '../state/settings_state.dart';
import '../dev_config.dart';
import 'http_client.dart';

/// Service for fetching missing tile preview images
class TilePreviewService {
  static const Duration _timeout = Duration(seconds: 10);
  static final _client = UserAgentClient();

  /// Attempt to fetch missing preview tiles for tile types that don't already have preview data
  /// Fails silently - no error handling or user notification on failure
  static Future<void> fetchMissingPreviews(SettingsState settingsState) async {
    try {
      bool anyUpdates = false;
      
      for (final provider in settingsState.tileProviders) {
        final updatedTileTypes = <TileType>[];
        bool providerNeedsUpdate = false;
        
        for (final tileType in provider.tileTypes) {
          // Only fetch if preview tile is missing
          if (tileType.previewTile == null) {
            // Skip if tile type requires API key but provider doesn't have one
            if (tileType.requiresApiKey && (provider.apiKey == null || provider.apiKey!.isEmpty)) {
              updatedTileTypes.add(tileType);
              continue;
            }

            final previewData = await _fetchPreviewForTileType(tileType, provider.apiKey);
            if (previewData != null) {
              // Create updated tile type with preview data
              final updatedTileType = tileType.copyWith(previewTile: previewData);
              updatedTileTypes.add(updatedTileType);
              providerNeedsUpdate = true;
            } else {
              updatedTileTypes.add(tileType);
            }
          } else {
            updatedTileTypes.add(tileType);
          }
        }
        
        if (providerNeedsUpdate) {
          final updatedProvider = provider.copyWith(tileTypes: updatedTileTypes);
          await settingsState.addOrUpdateTileProvider(updatedProvider);
          anyUpdates = true;
        }
      }
      
      if (anyUpdates) {
        debugPrint('TilePreviewService: Updated providers with new preview tiles');
      }
    } catch (e) {
      // Fail silently as requested
      debugPrint('TilePreviewService: Error during preview fetching: $e');
    }
  }

  static Future<Uint8List?> _fetchPreviewForTileType(TileType tileType, String? apiKey) async {
    try {
      final url = tileType.getTileUrl(kPreviewTileZoom, kPreviewTileX, kPreviewTileY, apiKey: apiKey);
      
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);
      
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        debugPrint('TilePreviewService: Fetched preview for ${tileType.name}');
        return response.bodyBytes;
      }
    } catch (e) {
      // Fail silently - just log for debugging
      debugPrint('TilePreviewService: Failed to fetch preview for ${tileType.name}: $e');
    }
    return null;
  }
}
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import 'map_data_provider.dart';
import 'offline_area_service.dart';

/// Custom tile provider that integrates with DeFlock's offline/online architecture.
/// 
/// This replaces the complex HTTP interception approach with a clean TileProvider 
/// implementation that directly interfaces with our MapDataProvider system.
class DeflockTileProvider extends TileProvider {
  final MapDataProvider _mapDataProvider = MapDataProvider();
  
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // Get current provider info to include in cache key
    final appState = AppState.instance;
    final providerId = appState.selectedTileProvider?.id ?? 'unknown';
    final tileTypeId = appState.selectedTileType?.id ?? 'unknown';
    
    return DeflockTileImageProvider(
      coordinates: coordinates,
      options: options,
      mapDataProvider: _mapDataProvider,
      providerId: providerId,
      tileTypeId: tileTypeId,
    );
  }
}

/// Image provider that fetches tiles through our MapDataProvider.
/// 
/// This handles the actual tile fetching using our existing offline/online
/// routing logic without any HTTP interception complexity.
class DeflockTileImageProvider extends ImageProvider<DeflockTileImageProvider> {
  final TileCoordinates coordinates;
  final TileLayer options;
  final MapDataProvider mapDataProvider;
  final String providerId;
  final String tileTypeId;
  
  const DeflockTileImageProvider({
    required this.coordinates,
    required this.options,
    required this.mapDataProvider,
    required this.providerId,
    required this.tileTypeId,
  });
  
  @override
  Future<DeflockTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<DeflockTileImageProvider>(this);
  }
  
  @override
  ImageStreamCompleter loadImage(DeflockTileImageProvider key, ImageDecoderCallback decode) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: 1.0,
    );
  }
  
  Future<Codec> _loadAsync(
    DeflockTileImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      // Get current tile provider and type from app state
      final appState = AppState.instance;
      final selectedProvider = appState.selectedTileProvider;
      final selectedTileType = appState.selectedTileType;
      
      if (selectedProvider == null || selectedTileType == null) {
        throw Exception('No tile provider configured');
      }
      
      // Smart cache routing: only check offline cache when needed
      final MapSource source = _shouldCheckOfflineCache(appState) 
          ? MapSource.auto  // Check offline first, then network
          : MapSource.remote; // Skip offline cache, go directly to network
      
      final tileBytes = await mapDataProvider.getTile(
        z: coordinates.z, 
        x: coordinates.x, 
        y: coordinates.y,
        source: source,
      );
      
      // Decode the image bytes
      final buffer = await ImmutableBuffer.fromUint8List(Uint8List.fromList(tileBytes));
      return await decode(buffer);
      
    } catch (e) {
      // Don't log routine offline misses to avoid console spam
      if (!e.toString().contains('offline mode is enabled')) {
        debugPrint('[DeflockTileProvider] Failed to load tile ${coordinates.z}/${coordinates.x}/${coordinates.y}: $e');
      }
      
      // Re-throw the exception and let FlutterMap handle missing tiles gracefully
      // This is better than trying to provide fallback images
      rethrow;
    }
  }
  
  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is DeflockTileImageProvider &&
           other.coordinates == coordinates &&
           other.providerId == providerId &&
           other.tileTypeId == tileTypeId;
  }
  
  @override
  int get hashCode => Object.hash(coordinates, providerId, tileTypeId);
  
  /// Determine if we should check offline cache for this tile request.
  /// Only check offline cache if:
  /// 1. We're in offline mode (forced), OR
  /// 2. We have offline areas for the current provider/type
  /// 
  /// This avoids expensive filesystem searches when browsing online
  /// with providers that have no offline areas.
  bool _shouldCheckOfflineCache(AppState appState) {
    // Always check offline cache in offline mode
    if (appState.offlineMode) {
      return true;
    }
    
    // For online mode, only check if we might actually have relevant offline data
    final currentProvider = appState.selectedTileProvider;
    final currentTileType = appState.selectedTileType;
    
    if (currentProvider == null || currentTileType == null) {
      return false;
    }
    
    // Quick check: do we have any offline areas for this provider/type?
    // This avoids the expensive per-tile filesystem search in fetchLocalTile
    final offlineService = OfflineAreaService();
    final hasRelevantAreas = offlineService.hasOfflineAreasForProvider(
      currentProvider.id, 
      currentTileType.id,
    );
    
    return hasRelevantAreas;
  }
}
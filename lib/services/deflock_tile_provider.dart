import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import '../app_state.dart';
import '../models/tile_provider.dart' as models;
import 'map_data_provider.dart';

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
      
      // Fetch tile through our existing MapDataProvider system
      // This automatically handles offline/online routing, caching, etc.
      final tileBytes = await mapDataProvider.getTile(
        z: coordinates.z, 
        x: coordinates.x, 
        y: coordinates.y,
        source: MapSource.auto, // Use auto routing (offline first, then online)
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
      throw e;
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
}
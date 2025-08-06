import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import '../models/osm_camera_node.dart';

/// Model for an offline area
enum OfflineAreaStatus { downloading, complete, error, cancelled }

class OfflineArea {
  final String id;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;
  final String directory; // base dir for area storage
  OfflineAreaStatus status;
  double progress; // 0.0 - 1.0
  int tilesDownloaded;
  int tilesTotal;
  List<OsmCameraNode> cameras;

  OfflineArea({
    required this.id,
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.directory,
    this.status = OfflineAreaStatus.downloading,
    this.progress = 0,
    this.tilesDownloaded = 0,
    this.tilesTotal = 0,
    this.cameras = const [],
  });
}

/// Service for managing download, storage, and retrieval of offline map areas and cameras.
class OfflineAreaService {
  static final OfflineAreaService _instance = OfflineAreaService._();
  factory OfflineAreaService() => _instance;
  OfflineAreaService._();

  final List<OfflineArea> _areas = [];

  List<OfflineArea> get offlineAreas => List.unmodifiable(_areas);

  /// Start downloading an area: tiles and camera points.
  /// [onProgress] is called with 0.0..1.0, [onComplete] when finished or failed.
  Future<void> downloadArea({
    required String id,
    required LatLngBounds bounds,
    required int minZoom,
    required int maxZoom,
    required String directory,
    void Function(double progress)? onProgress,
    void Function(OfflineAreaStatus status)? onComplete,
  }) async {
    final area = OfflineArea(
      id: id,
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      directory: directory,
    );
    _areas.add(area);

    try {
      // STEP 1: Tiles (incl. global z=1..4)
      final tileTasks = _computeTileList(bounds, minZoom, maxZoom);
      final globalTiles = _computeTileList(_globalWorldBounds(), 1, 4);
      final allTiles = {...tileTasks, ...globalTiles};
      area.tilesTotal = allTiles.length;

      int done = 0;
      for (final tile in allTiles) {
        if (area.status == OfflineAreaStatus.cancelled) break;
        await _downloadTile(tile[0], tile[1], tile[2], directory);
        done++;
        area.tilesDownloaded = done;
        area.progress = done / area.tilesTotal;
        if (onProgress != null) onProgress(area.progress);
      }

      // STEP 2: Fetch cameras for this bbox (all, not limited!)
      final cameras = await _downloadAllCameras(bounds);
      area.cameras = cameras;
      await _saveCameras(cameras, directory);

      area.status = OfflineAreaStatus.complete;
      area.progress = 1.0;
      if (onComplete != null) onComplete(area.status);
    } catch (e) {
      area.status = OfflineAreaStatus.error;
      if (onComplete != null) onComplete(area.status);
    }
  }

  void cancelDownload(String id) {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    area.status = OfflineAreaStatus.cancelled;
  }

  void deleteArea(String id) async {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    Directory(area.directory).delete(recursive: true);
    _areas.remove(area);
  }

  // --- TILE LOGIC ---

  /// Returns set of [z, x, y] tuples needed to cover [bounds] at [zMin]..[zMax].
  Set<List<int>> _computeTileList(LatLngBounds bounds, int zMin, int zMax) {
    Set<List<int>> tiles = {};
    for (int z = zMin; z <= zMax; z++) {
      final minTile = _latLonToTile(bounds.southWest.latitude, bounds.southWest.longitude, z);
      final maxTile = _latLonToTile(bounds.northEast.latitude, bounds.northEast.longitude, z);
      for (int x = minTile[0]; x <= maxTile[0]; x++) {
        for (int y = minTile[1]; y <= maxTile[1]; y++) {
          tiles.add([z, x, y]);
        }
      }
    }
    return tiles;
  }

  /// Converts lat/lon+zoom to OSM tile xy as [x, y]
  List<int> _latLonToTile(double lat, double lon, int zoom) {
    final n = pow(2.0, zoom);
    final xtile = ((lon + 180.0) / 360.0 * n).floor();
    final ytile = ((1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * n).floor();
    return [xtile, ytile];
  }

  LatLngBounds _globalWorldBounds() {
    return LatLngBounds(LatLng(-85.0511, -180.0), LatLng(85.0511, 180.0));
  }

  Future<void> _downloadTile(int z, int x, int y, String baseDir) async {
    final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
    final dir = Directory('$baseDir/tiles/$z/$x');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$y.png');
    if (await file.exists()) return; // already downloaded
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      await file.writeAsBytes(resp.bodyBytes);
    } else {
      throw Exception('Failed to download tile $z/$x/$y');
    }
  }

  // --- CAMERA LOGIC ---
  Future<List<OsmCameraNode>> _downloadAllCameras(LatLngBounds bounds) async {
    // Overpass QL: fetch all cameras with no limit.
    final sw = bounds.southWest;
    final ne = bounds.northEast;
    final bbox = [sw.latitude, sw.longitude, ne.latitude, ne.longitude].join(',');
    final query = '[out:json][timeout:60];node["man_made"="surveillance"]["camera:mount"="pole"]($bbox);out body;';
    final url = 'https://overpass-api.de/api/interpreter';
    final resp = await http.post(Uri.parse(url), body: { 'data': query });
    if (resp.statusCode != 200) {
      throw Exception('Failed to fetch cameras');
    }
    final data = jsonDecode(resp.body);
    return (data['elements'] as List<dynamic>?)?.map((e) => OsmCameraNode.fromJson(e)).toList() ?? [];
  }

  Future<void> _saveCameras(List<OsmCameraNode> cams, String dir) async {
    final file = File('$dir/cameras.json');
    await file.writeAsString(jsonEncode(cams.map((c) => c.toJson()).toList()));
  }
}

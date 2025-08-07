import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:path_provider/path_provider.dart';
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'bounds': {
      'sw': {'lat': bounds.southWest.latitude, 'lng': bounds.southWest.longitude},
      'ne': {'lat': bounds.northEast.latitude, 'lng': bounds.northEast.longitude},
    },
    'minZoom': minZoom,
    'maxZoom': maxZoom,
    'directory': directory,
    'status': status.name,
    'progress': progress,
    'tilesDownloaded': tilesDownloaded,
    'tilesTotal': tilesTotal,
    'cameras': cameras.map((c) => c.toJson()).toList(),
  };

  static OfflineArea fromJson(Map<String, dynamic> json) {
    final bounds = LatLngBounds(
      LatLng(json['bounds']['sw']['lat'], json['bounds']['sw']['lng']),
      LatLng(json['bounds']['ne']['lat'], json['bounds']['ne']['lng']),
    );
    return OfflineArea(
      id: json['id'],
      bounds: bounds,
      minZoom: json['minZoom'],
      maxZoom: json['maxZoom'],
      directory: json['directory'],
      status: OfflineAreaStatus.values.firstWhere(
        (e) => e.name == json['status'], orElse: () => OfflineAreaStatus.error),
      progress: (json['progress'] ?? 0).toDouble(),
      tilesDownloaded: json['tilesDownloaded'] ?? 0,
      tilesTotal: json['tilesTotal'] ?? 0,
      cameras: (json['cameras'] as List? ?? [])
          .map((e) => OsmCameraNode.fromJson(e)).toList(),
    );
  }
}

/// Service for managing download, storage, and retrieval of offline map areas and cameras.
class OfflineAreaService {
  static final OfflineAreaService _instance = OfflineAreaService._();
  factory OfflineAreaService() => _instance;
  OfflineAreaService._() {
    _loadAreasFromDisk();
  }

  final List<OfflineArea> _areas = [];

  /// Where offline area data/metadata lives
  Future<Directory> getOfflineAreaDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final areaRoot = Directory("${dir.path}/offline_areas");
    if (!areaRoot.existsSync()) {
      areaRoot.createSync(recursive: true);
    }
    return areaRoot;
  }

  Future<File> _getMetadataPath() async {
    final dir = await getOfflineAreaDir();
    return File("${dir.path}/offline_areas.json");
  }

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
    await _saveAreasToDisk();

    try {
      // STEP 1: Tiles (incl. global z=1..4)
      final tileTasks = computeTileList(bounds, minZoom, maxZoom);
      final globalTiles = computeTileList(globalWorldBounds(), 1, 4);
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
        await _saveAreasToDisk();
      }

      // STEP 2: Fetch cameras for this bbox (all, not limited!)
      final cameras = await _downloadAllCameras(bounds);
      area.cameras = cameras;
      await _saveCameras(cameras, directory);

      area.status = OfflineAreaStatus.complete;
      area.progress = 1.0;
      await _saveAreasToDisk();
      if (onComplete != null) onComplete(area.status);
    } catch (e) {
      area.status = OfflineAreaStatus.error;
      await _saveAreasToDisk();
      if (onComplete != null) onComplete(area.status);
    }
  }

  void cancelDownload(String id) {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    area.status = OfflineAreaStatus.cancelled;
    _saveAreasToDisk();
  }

  void deleteArea(String id) async {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    await Directory(area.directory).delete(recursive: true);
    _areas.remove(area);
    await _saveAreasToDisk();
  }

  // --- PERSISTENCE LOGIC ---

  Future<void> _saveAreasToDisk() async {
    try {
      final file = await _getMetadataPath();
      final content = jsonEncode(_areas.map((a) => a.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Failed to save offline areas: $e');
    }
  }

  Future<void> _loadAreasFromDisk() async {
    try {
      final file = await _getMetadataPath();
      if (!(await file.exists())) return;
      final str = await file.readAsString();
      final data = jsonDecode(str);
      _areas.clear();
      for (final areaJson in (data as List)) {
        final area = OfflineArea.fromJson(areaJson);
        // Check if directory still exists; adjust status if not
        if (!Directory(area.directory).existsSync()) {
          area.status = OfflineAreaStatus.error;
        }
        _areas.add(area);
      }
    } catch (e) {
      debugPrint('Failed to load offline areas: $e');
    }
  }

  // --- TILE LOGIC ---

  /// Returns set of [z, x, y] tuples needed to cover [bounds] at [zMin]..[zMax].
  Set<List<int>> computeTileList(LatLngBounds bounds, int zMin, int zMax) {
    // Now a public method to support dialog estimation.
    Set<List<int>> tiles = {};
    for (int z = zMin; z <= zMax; z++) {
      // Lower bounds: .floor(), upper bounds: .ceil()-1 for inclusivity
      final minTile = _latLonToTile(bounds.southWest.latitude, bounds.southWest.longitude, z);
      final neTileRaw = _latLonToTileRaw(bounds.northEast.latitude, bounds.northEast.longitude, z);
      final maxX = neTileRaw[0].ceil() - 1;
      final maxY = neTileRaw[1].ceil() - 1;
      final minX = minTile[0];
      final minY = minTile[1];
      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          tiles.add([z, x, y]);
        }
      }
    }
    return tiles;
  }

  // Returns x, y as double for NE corners
  List<double> _latLonToTileRaw(double lat, double lon, int zoom) {
    final n = pow(2.0, zoom);
    final xtile = (lon + 180.0) / 360.0 * n;
    final ytile = (1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * n;
    return [xtile, ytile];
  }

  /// Finds the minimum zoom at which a single tile covers [bounds].
  /// Returns the highest z (up to [maxSearchZoom]) for which both corners are in the same tile.
  int findDynamicMinZoom(LatLngBounds bounds, {int maxSearchZoom = 19}) {
    for (int z = 1; z <= maxSearchZoom; z++) {
      final swTile = _latLonToTile(bounds.southWest.latitude, bounds.southWest.longitude, z);
      final neTile = _latLonToTile(bounds.northEast.latitude, bounds.northEast.longitude, z);
      if (swTile[0] != neTile[0] || swTile[1] != neTile[1]) {
        return z - 1 > 0 ? z - 1 : 1;
      }
    }
    return maxSearchZoom;
  }

  /// Converts lat/lon+zoom to OSM tile xy as [x, y]
  List<int> _latLonToTile(double lat, double lon, int zoom) {
    final n = pow(2.0, zoom);
    final xtile = ((lon + 180.0) / 360.0 * n).floor();
    final ytile = ((1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * n).floor();
    return [xtile, ytile];
  }

  LatLngBounds globalWorldBounds() {
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

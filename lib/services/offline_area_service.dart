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
  String name;
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;
  final String directory; // base dir for area storage
  OfflineAreaStatus status;
  double progress; // 0.0 - 1.0
  int tilesDownloaded;
  int tilesTotal;
  List<OsmCameraNode> cameras;
  int sizeBytes; // Disk size in bytes
  final bool isPermanent; // Not user-deletable if true

  OfflineArea({
    required this.id,
    this.name = '',
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
    required this.directory,
    this.status = OfflineAreaStatus.downloading,
    this.progress = 0,
    this.tilesDownloaded = 0,
    this.tilesTotal = 0,
    this.cameras = const [],
    this.sizeBytes = 0,
    this.isPermanent = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
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
    'sizeBytes': sizeBytes,
    'isPermanent': isPermanent,
  };

  static OfflineArea fromJson(Map<String, dynamic> json) {
    final bounds = LatLngBounds(
      LatLng(json['bounds']['sw']['lat'], json['bounds']['sw']['lng']),
      LatLng(json['bounds']['ne']['lat'], json['bounds']['ne']['lng']),
    );
    return OfflineArea(
      id: json['id'],
      name: json['name'] ?? '',
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
      sizeBytes: json['sizeBytes'] ?? 0,
      isPermanent: json['isPermanent'] ?? false,
    );
  }
}

/// Service for managing download, storage, and retrieval of offline map areas and cameras.
class OfflineAreaService {
  // Public wrapper to allow UI code to persist area changes
  // Wrapper removed; see implementation at line 204
  /// Compute area disk usage (recursive)
  Future<int> getAreaSizeBytes(OfflineArea area) async {
    int total = 0;
    final dir = Directory(area.directory);
    if (await dir.exists()) {
      await for (var fse in dir.list(recursive: true)) {
        if (fse is File) {
          total += await fse.length();
        }
      }
    }
    area.sizeBytes = total;
    await saveAreasToDisk();
    return total;
  }

  static final OfflineAreaService _instance = OfflineAreaService._();
  factory OfflineAreaService() => _instance;
  OfflineAreaService._() {
    _loadAreasFromDisk().then((_) => _ensureAndAutoDownloadWorldArea());
  }

  // Ensure permanent world area exists and auto-download if tiles missing
  Future<void> _ensureAndAutoDownloadWorldArea() async {
    final dir = await getOfflineAreaDir();
    final worldDir = "${dir.path}/world_z1_4";
    final LatLngBounds worldBounds = globalWorldBounds();
    OfflineArea? world;
    for (final a in _areas) {
      if (a.isPermanent) { world = a; break; }
    }
    final Set<List<int>> expectedTiles = computeTileList(worldBounds, 1, 4);

    // Recount actual files if world area exists (can be slow but only on launch or change)
    if (world != null) {
      int filesFound = 0;
      List<List<int>> missingTiles = [];
      for (final tile in expectedTiles) {
        final f = File('${world.directory}/tiles/${tile[0]}/${tile[1]}/${tile[2]}.png');
        if (f.existsSync()) {
          filesFound++;
        } else if (missingTiles.length < 10) {
          missingTiles.add(tile);
        }
      }
      if (filesFound != expectedTiles.length) {
        debugPrint('World area: missing \\${expectedTiles.length - filesFound} tiles. First few: \\$missingTiles');
      } else {
        debugPrint('World area: all tiles accounted for.');
      }

      world.tilesTotal = expectedTiles.length;
      world.tilesDownloaded = filesFound;
      world.progress = (world.tilesTotal == 0) ? 0.0 : (filesFound / world.tilesTotal);
      if (filesFound == world.tilesTotal) {
        world.status = OfflineAreaStatus.complete;
        await saveAreasToDisk();
        return;
      } else {
        world.status = OfflineAreaStatus.downloading;
        await saveAreasToDisk();
        downloadArea(
          id: world.id,
          bounds: world.bounds,
          minZoom: world.minZoom,
          maxZoom: world.maxZoom,
          directory: world.directory,
          name: world.name,
          onProgress: null,
          onComplete: null,
        );
        return;
      }
    }
    // If not present, create and start download
    world = OfflineArea(
      id: 'permanent_world_z1_4',
      name: 'World (zoom 1-4)',
      bounds: worldBounds,
      minZoom: 1,
      maxZoom: 4,
      directory: worldDir,
      status: OfflineAreaStatus.downloading,
      progress: 0.0,
      isPermanent: true,
      tilesTotal: expectedTiles.length,
      tilesDownloaded: 0,
    );
    _areas.insert(0, world);
    await saveAreasToDisk();
    downloadArea(
      id: world.id,
      bounds: world.bounds,
      minZoom: world.minZoom,
      maxZoom: world.maxZoom,
      directory: world.directory,
      name: world.name,
      onProgress: null,
      onComplete: null,
    );
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
    String? name,
  }) async {
    // If area with same id exists, replace its contents, else add.
    OfflineArea? area;
    for (final a in _areas) {
      if (a.id == id) { area = a; break; }
    }
    if (area != null) {
      // Remove area and its files before creating fresh
      _areas.remove(area);
      final dirObj = Directory(area.directory);
      if (await dirObj.exists()) {
        await dirObj.delete(recursive: true);
      }
    }
    area = OfflineArea(
      id: id,
      name: name ?? area?.name ?? '',
      bounds: bounds,
      minZoom: minZoom,
      maxZoom: maxZoom,
      directory: directory,
      isPermanent: area?.isPermanent ?? false,
    );
    _areas.add(area);
    await saveAreasToDisk();

    try {
      // STEP 1: Tiles: user areas get only their bbox/zooms; world area gets only global z=1..4
      Set<List<int>> allTiles;
      if (area.isPermanent) {
        allTiles = computeTileList(globalWorldBounds(), 1, 4);
      } else {
        allTiles = computeTileList(bounds, minZoom, maxZoom);
      }
      area.tilesTotal = allTiles.length;

      int done = 0;
      for (final tile in allTiles) {
        if (area.status == OfflineAreaStatus.cancelled) break;
        await _downloadTile(tile[0], tile[1], tile[2], directory);
        done++;
        area.tilesDownloaded = done;
        area.progress = done / area.tilesTotal;
        if (onProgress != null) onProgress(area.progress);
        await getAreaSizeBytes(area); // Update size as we download
        await saveAreasToDisk();
      }

      // STEP 2: Fetch cameras for this bbox (all, not limited!)
      if (!area.isPermanent) {
        final cameras = await _downloadAllCameras(bounds);
        area.cameras = cameras;
        await _saveCameras(cameras, directory);
      } else {
        area.cameras = [];
      }
      await getAreaSizeBytes(area);

      area.status = OfflineAreaStatus.complete;
      area.progress = 1.0;
      await saveAreasToDisk();
      if (onComplete != null) onComplete(area.status);
    } catch (e) {
      area.status = OfflineAreaStatus.error;
      await saveAreasToDisk();
      if (onComplete != null) onComplete(area.status);
    }
  }

  void cancelDownload(String id) async {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    area.status = OfflineAreaStatus.cancelled;
    // Delete partial files as on standard delete
    final dir = Directory(area.directory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _areas.remove(area); // always remove, world will get recreated/refetched as needed
    await saveAreasToDisk();
    if (area.isPermanent) {
      // Immediately recreate and auto-download world area
      _ensureAndAutoDownloadWorldArea();
    }
  }

  void deleteArea(String id) async {
    final area = _areas.firstWhere((a) => a.id == id, orElse: () => throw 'Area not found');
    final dir = Directory(area.directory);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _areas.remove(area);
    await saveAreasToDisk();
  }

  // --- PERSISTENCE LOGIC ---

  Future<void> saveAreasToDisk() async {
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
      if (str.trim().isEmpty) return;
      late final List data;
      try {
        data = jsonDecode(str);
      } catch (e) {
        debugPrint('Failed to parse offline areas json: $e');
        return;
      }
      _areas.clear();
      for (final areaJson in data) {
        final area = OfflineArea.fromJson(areaJson);
        // Check if directory still exists; adjust status if not
        if (!Directory(area.directory).existsSync()) {
          area.status = OfflineAreaStatus.error;
        } else {
          // Update sizeBytes async
          getAreaSizeBytes(area);
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
  Set<List<int>> tiles = {};
  const double epsilon = 1e-7;
  double latMin = min(bounds.southWest.latitude, bounds.northEast.latitude);
  double latMax = max(bounds.southWest.latitude, bounds.northEast.latitude);
  double lonMin = min(bounds.southWest.longitude, bounds.northEast.longitude);
  double lonMax = max(bounds.southWest.longitude, bounds.northEast.longitude);
  // Expand degenerate/flat areas a hair
  if ((latMax - latMin).abs() < epsilon) {
    latMin -= epsilon;
    latMax += epsilon;
  }
  if ((lonMax - lonMin).abs() < epsilon) {
    lonMin -= epsilon;
    lonMax += epsilon;
  }
for (int z = zMin; z <= zMax; z++) {
  final n = pow(2, z).toInt();
  final minTile = _latLonToTile(latMin, lonMin, z);
  final maxTile = _latLonToTile(latMax, lonMax, z);
  final minX = min(minTile[0], maxTile[0]);
  final maxX = max(minTile[0], maxTile[0]);
  final minY = min(minTile[1], maxTile[1]);
  final maxY = max(minTile[1], maxTile[1]);

  // New diagnostics!
    // Removed verbose debugPrint analysis outputs
  for (int x = minX; x <= maxX; x++) {
    for (int y = minY; y <= maxY; y++) {
      tiles.add([z, x, y]);
    }
  }
    // Removed verbose debugPrint tile add outputs
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
    // Use slightly shrunken bounds to avoid tile index overflow at extreme coordinates
    return LatLngBounds(LatLng(-85.0, -179.9), LatLng(85.0, 179.9));
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

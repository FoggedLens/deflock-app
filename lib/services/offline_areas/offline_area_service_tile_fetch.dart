import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../../models/osm_camera_node.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;

Future<void> downloadTile(int z, int x, int y, String baseDir) async {
  final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
  final dir = Directory('$baseDir/tiles/$z/$x');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$y.png');
  if (await file.exists()) return; // already downloaded
  const int maxAttempts = 3;
  int attempt = 0;
  final random = Random();
  final delays = [0, 3000 + random.nextInt(1000) - 500, 10000 + random.nextInt(4000) - 2000];
  while (true) {
    try {
      attempt++;
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        await file.writeAsBytes(resp.bodyBytes);
        return;
      } else {
        throw Exception('Failed to download tile $z/$x/$y (status \\${resp.statusCode})');
      }
    } catch (e) {
      if (attempt >= maxAttempts) {
      throw Exception("Failed to download tile $z/$x/$y after $attempt attempts: $e");
      }
      final delay = delays[attempt-1].clamp(0, 60000);
      await Future.delayed(Duration(milliseconds: delay));
    }
  }
}

Future<List<OsmCameraNode>> downloadAllCameras(LatLngBounds bounds) async {
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

Future<void> saveCameras(List<OsmCameraNode> cams, String dir) async {
  final file = File('$dir/cameras.json');
  await file.writeAsString(jsonEncode(cams.map((c) => c.toJson()).toList()));
}

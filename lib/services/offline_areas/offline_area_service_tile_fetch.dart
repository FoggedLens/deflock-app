import 'dart:io';
import 'dart:convert';
import '../../models/osm_camera_node.dart';

/// Disk IO utilities for offline area file management ONLY. No network requests should occur here.

/// Save-to-disk for a tile that has already been fetched elsewhere.
Future<void> saveTileBytes(int z, int x, int y, String baseDir, List<int> bytes) async {
  final dir = Directory('$baseDir/tiles/$z/$x');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$y.png');
  await file.writeAsBytes(bytes);
}

/// Save-to-disk for cameras.json; called only by OfflineAreaService during area download
Future<void> saveCameras(List<OsmCameraNode> cams, String dir) async {
  final file = File('$dir/cameras.json');
  await file.writeAsString(jsonEncode(cams.map((c) => c.toJson()).toList()));
}

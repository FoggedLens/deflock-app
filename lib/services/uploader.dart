import 'dart:async';
import 'package:http/http.dart' as http;

import '../models/pending_upload.dart';

class Uploader {
  Uploader(this.accessToken, this.onSuccess);

  final String accessToken;
  final void Function() onSuccess;

  Future<bool> upload(PendingUpload p) async {
    try {
      print('Uploader: Starting upload for camera at ${p.coord.latitude}, ${p.coord.longitude}');
      
      // 1. open changeset
      final csXml = '''
        <osm>
          <changeset>
            <tag k="created_by" v="FlockMap 0.5"/>
            <tag k="comment" v="Add surveillance camera"/>
          </changeset>
        </osm>''';
      print('Uploader: Creating changeset...');
      final csResp = await _put('/api/0.6/changeset/create', csXml);
      print('Uploader: Changeset response: ${csResp.statusCode} - ${csResp.body}');
      if (csResp.statusCode != 200) {
        print('Uploader: Failed to create changeset');
        return false;
      }
      final csId = csResp.body.trim();
      print('Uploader: Created changeset ID: $csId');

      // 2. create node
      final nodeXml = '''
        <osm>
          <node changeset="$csId" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            <tag k="man_made" v="surveillance"/>
            <tag k="surveillance:type" v="ALPR"/>
            <tag k="camera:type" v="fixed"/>
            <tag k="direction" v="${p.direction.round()}"/>
          </node>
        </osm>''';
      print('Uploader: Creating node...');
      final nodeResp = await _put('/api/0.6/node/create', nodeXml);
      print('Uploader: Node response: ${nodeResp.statusCode} - ${nodeResp.body}');
      if (nodeResp.statusCode != 200) {
        print('Uploader: Failed to create node');
        return false;
      }
      final nodeId = nodeResp.body.trim();
      print('Uploader: Created node ID: $nodeId');

      // 3. close changeset
      print('Uploader: Closing changeset...');
      final closeResp = await _put('/api/0.6/changeset/$csId/close', '');
      print('Uploader: Close response: ${closeResp.statusCode}');

      print('Uploader: Upload successful!');
      onSuccess();
      return true;
    } catch (e) {
      print('Uploader: Upload failed with error: $e');
      return false;
    }
  }

  Future<http.Response> _post(String path, String body) => http.post(
        Uri.https('api.openstreetmap.org', path),
        headers: _headers,
        body: body,
      );

  Future<http.Response> _put(String path, String body) => http.put(
        Uri.https('api.openstreetmap.org', path),
        headers: _headers,
        body: body,
      );

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'text/xml',
      };
}


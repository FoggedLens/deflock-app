import 'dart:async';
import 'package:http/http.dart' as http;

import '../models/pending_upload.dart';
import '../dev_config.dart';
import '../app_state.dart';

class Uploader {
  Uploader(this.accessToken, this.onSuccess, {this.uploadMode = UploadMode.production});

  final String accessToken;
  final void Function() onSuccess;
  final UploadMode uploadMode;

  Future<bool> upload(PendingUpload p) async {
    try {
      print('Uploader: Starting upload for camera at ${p.coord.latitude}, ${p.coord.longitude}');
      
      // 1. open changeset
      final csXml = '''
        <osm>
          <changeset>
            <tag k="created_by" v="$kClientName $kClientVersion"/>
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

      // 2. create or update node
      final mergedTags = Map<String, String>.from(p.profile.tags)
        ..['direction'] = p.direction.round().toString();
      final tagsXml = mergedTags.entries.map((e) =>
        '<tag k="${e.key}" v="${e.value}"/>').join('\n            ');
      
      final http.Response nodeResp;
      final String nodeId;
      
      if (p.isEdit) {
        // Update existing node
        final nodeXml = '''
        <osm>
          <node changeset="$csId" id="${p.originalNodeId}" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            $tagsXml
          </node>
        </osm>''';
        print('Uploader: Updating node ${p.originalNodeId}...');
        nodeResp = await _put('/api/0.6/node/${p.originalNodeId}', nodeXml);
        nodeId = p.originalNodeId.toString();
      } else {
        // Create new node
        final nodeXml = '''
        <osm>
          <node changeset="$csId" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            $tagsXml
          </node>
        </osm>''';
        print('Uploader: Creating new node...');
        nodeResp = await _put('/api/0.6/node/create', nodeXml);
        nodeId = nodeResp.body.trim();
      }
      
      print('Uploader: Node response: ${nodeResp.statusCode} - ${nodeResp.body}');
      if (nodeResp.statusCode != 200) {
        print('Uploader: Failed to ${p.isEdit ? "update" : "create"} node');
        return false;
      }
      print('Uploader: ${p.isEdit ? "Updated" : "Created"} node ID: $nodeId');

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

  String get _host {
    switch (uploadMode) {
      case UploadMode.sandbox:
        return 'api06.dev.openstreetmap.org';
      case UploadMode.production:
      default:
        return 'api.openstreetmap.org';
    }
  }

  Future<http.Response> _post(String path, String body) => http.post(
        Uri.https(_host, path),
        headers: _headers,
        body: body,
      );

  Future<http.Response> _put(String path, String body) => http.put(
        Uri.https(_host, path),
        headers: _headers,
        body: body,
      );

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'text/xml',
      };
}


import 'dart:async';
import 'package:http/http.dart' as http;

import '../models/pending_upload.dart';

class Uploader {
  Uploader(this.accessToken, this.onSuccess);

  final String accessToken;
  final void Function() onSuccess;

  Future<bool> upload(PendingUpload p) async {
    try {
      // 1. open changeset
      final csXml = '''
        <osm>
          <changeset>
            <tag k="created_by" v="FlockMap 0.5"/>
            <tag k="comment" v="Add surveillance camera"/>
          </changeset>
        </osm>''';
      final csResp = await _post('/api/0.6/changeset/create', csXml);
      if (csResp.statusCode != 200) return false;
      final csId = csResp.body;

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
      final nodeResp = await _put('/api/0.6/node/create', nodeXml);
      if (nodeResp.statusCode != 200) return false;

      // 3. close changeset
      await _put('/api/0.6/changeset/$csId/close', '');

      onSuccess();
      return true;
    } catch (_) {
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


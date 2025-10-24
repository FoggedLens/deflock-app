import 'dart:async';
import 'package:http/http.dart' as http;

import '../models/pending_upload.dart';
import '../dev_config.dart';
import 'version_service.dart';
import '../app_state.dart';

class Uploader {
  Uploader(this.accessToken, this.onSuccess, {this.uploadMode = UploadMode.production});

  final String accessToken;
  final void Function(int nodeId) onSuccess;
  final UploadMode uploadMode;

  Future<bool> upload(PendingUpload p) async {
    try {
      print('Uploader: Starting upload for node at ${p.coord.latitude}, ${p.coord.longitude}');
      
      // Safety check: create and modify operations MUST have profiles
      if ((p.operation == UploadOperation.create || p.operation == UploadOperation.modify) && p.profile == null) {
        print('Uploader: ERROR - ${p.operation.name} operation attempted without profile data');
        return false;
      }
      
      // 1. open changeset
      String action;
      switch (p.operation) {
        case UploadOperation.create:
          action = 'Add';
          break;
        case UploadOperation.modify:
          action = 'Update';
          break;
        case UploadOperation.delete:
          action = 'Delete';
          break;
      }
      // Generate appropriate comment based on operation type
      final profileName = p.profile?.name ?? 'surveillance';
      final csXml = '''
        <osm>
          <changeset>
            <tag k="created_by" v="$kClientName ${VersionService().version}"/>
            <tag k="comment" v="$action $profileName surveillance node"/>
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

      // 2. create, update, or delete node
      final http.Response nodeResp;
      final String nodeId;
      
      switch (p.operation) {
        case UploadOperation.create:
          // Create new node
          final mergedTags = p.getCombinedTags();
          final tagsXml = mergedTags.entries.map((e) =>
            '<tag k="${e.key}" v="${e.value}"/>').join('\n            ');
          final nodeXml = '''
        <osm>
          <node changeset="$csId" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            $tagsXml
          </node>
        </osm>''';
          print('Uploader: Creating new node...');
          nodeResp = await _put('/api/0.6/node/create', nodeXml);
          nodeId = nodeResp.body.trim();
          break;

        case UploadOperation.modify:
          // First, fetch the current node to get its version
          print('Uploader: Fetching current node ${p.originalNodeId} to get version...');
          final currentNodeResp = await _get('/api/0.6/node/${p.originalNodeId}');
          print('Uploader: Current node response: ${currentNodeResp.statusCode}');
          if (currentNodeResp.statusCode != 200) {
            print('Uploader: Failed to fetch current node');
            return false;
          }
          
          // Parse version from the response XML
          final currentNodeXml = currentNodeResp.body;
          final versionMatch = RegExp(r'version="(\d+)"').firstMatch(currentNodeXml);
          if (versionMatch == null) {
            print('Uploader: Could not parse version from current node XML');
            return false;
          }
          final currentVersion = versionMatch.group(1)!;
          print('Uploader: Current node version: $currentVersion');
          
          // Update existing node with version
          final mergedTags = p.getCombinedTags();
          final tagsXml = mergedTags.entries.map((e) =>
            '<tag k="${e.key}" v="${e.value}"/>').join('\n            ');
          final nodeXml = '''
        <osm>
          <node changeset="$csId" id="${p.originalNodeId}" version="$currentVersion" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            $tagsXml
          </node>
        </osm>''';
          print('Uploader: Updating node ${p.originalNodeId}...');
          nodeResp = await _put('/api/0.6/node/${p.originalNodeId}', nodeXml);
          nodeId = p.originalNodeId.toString();
          break;

        case UploadOperation.delete:
          // First, fetch the current node to get its version and coordinates
          print('Uploader: Fetching current node ${p.originalNodeId} for deletion...');
          final currentNodeResp = await _get('/api/0.6/node/${p.originalNodeId}');
          print('Uploader: Current node response: ${currentNodeResp.statusCode}');
          if (currentNodeResp.statusCode != 200) {
            print('Uploader: Failed to fetch current node');
            return false;
          }
          
          // Parse version and tags from the response XML
          final currentNodeXml = currentNodeResp.body;
          final versionMatch = RegExp(r'version="(\d+)"').firstMatch(currentNodeXml);
          if (versionMatch == null) {
            print('Uploader: Could not parse version from current node XML');
            return false;
          }
          final currentVersion = versionMatch.group(1)!;
          print('Uploader: Current node version: $currentVersion');
          
          // Delete node - OSM requires current tags and coordinates
          final nodeXml = '''
        <osm>
          <node changeset="$csId" id="${p.originalNodeId}" version="$currentVersion" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
          </node>
        </osm>''';
          print('Uploader: Deleting node ${p.originalNodeId}...');
          nodeResp = await _delete('/api/0.6/node/${p.originalNodeId}', nodeXml);
          nodeId = p.originalNodeId.toString();
          break;
      }
      
      print('Uploader: Node response: ${nodeResp.statusCode} - ${nodeResp.body}');
      if (nodeResp.statusCode != 200) {
        print('Uploader: Failed to ${p.operation.name} node');
        return false;
      }
      print('Uploader: ${p.operation.name.capitalize()} node ID: $nodeId');

      // 3. close changeset
      print('Uploader: Closing changeset...');
      final closeResp = await _put('/api/0.6/changeset/$csId/close', '');
      print('Uploader: Close response: ${closeResp.statusCode}');

      print('Uploader: Upload successful!');
      final nodeIdInt = int.parse(nodeId);
      onSuccess(nodeIdInt);
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

  Future<http.Response> _get(String path) => http.get(
        Uri.https(_host, path),
        headers: _headers,
      );

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

  Future<http.Response> _delete(String path, String body) => http.delete(
        Uri.https(_host, path),
        headers: _headers,
        body: body,
      );

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'text/xml',
      };
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}


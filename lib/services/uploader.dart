import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pending_upload.dart';
import '../dev_config.dart';
import '../state/settings_state.dart';
import 'version_service.dart';

class UploadResult {
  final bool success;
  final String? errorMessage;
  final String? changesetId; // For changeset creation results
  final int? nodeId; // For node operation results  
  final bool changesetNotFound; // Special flag for 404 case during close

  UploadResult.success({
    this.changesetId,
    this.nodeId,
  }) : success = true, errorMessage = null, changesetNotFound = false;

  UploadResult.failure({
    required this.errorMessage,
    this.changesetNotFound = false,
    this.changesetId,
    this.nodeId,
  }) : success = false;

  // Legacy compatibility for simulate mode and full upload method
  bool get isFullySuccessful => success;
  bool get changesetCreateSuccess => success;
  bool get nodeOperationSuccess => success; 
  bool get changesetCloseSuccess => success;
  bool get hasOrphanedChangeset => changesetId != null && !success;
}

class Uploader {
  Uploader(this.accessToken, this.onSuccess, this.onError, {this.uploadMode = UploadMode.production});

  final String accessToken;
  final void Function(int nodeId) onSuccess;
  final void Function(String errorMessage) onError;
  final UploadMode uploadMode;

  // Create changeset (step 1 of 3)
  Future<UploadResult> createChangeset(PendingUpload p) async {
    try {
      debugPrint('[Uploader] Creating changeset for ${p.operation.name} operation...');
      
      // Safety check: create, modify, and extract operations MUST have profiles
      if ((p.operation == UploadOperation.create || p.operation == UploadOperation.modify || p.operation == UploadOperation.extract) && p.profile == null) {
        final errorMsg = 'Missing profile data for ${p.operation.name} operation';
        debugPrint('[Uploader] ERROR - $errorMsg');
        return UploadResult.failure(errorMessage: errorMsg);
      }
      
      // Use the user's changeset comment, with XML sanitization
      final sanitizedComment = _sanitizeXmlText(p.changesetComment);
      final csXml = '''
        <osm>
          <changeset>
            <tag k="created_by" v="$kClientName ${VersionService().version}"/>
            <tag k="comment" v="$sanitizedComment"/>
          </changeset>
        </osm>''';
      
      debugPrint('[Uploader] Creating changeset...');
      final csResp = await _put('/api/0.6/changeset/create', csXml);
      debugPrint('[Uploader] Changeset response: ${csResp.statusCode} - ${csResp.body}');
      
      if (csResp.statusCode != 200) {
        final errorMsg = 'Failed to create changeset: HTTP ${csResp.statusCode} - ${csResp.body}';
        debugPrint('[Uploader] $errorMsg');
        return UploadResult.failure(errorMessage: errorMsg);
      }
      
      final csId = csResp.body.trim();
      debugPrint('[Uploader] Created changeset ID: $csId');
      
      return UploadResult.success(changesetId: csId);
      
    } on TimeoutException catch (e) {
      final errorMsg = 'Changeset creation timed out after ${kUploadHttpTimeout.inSeconds}s: $e';
      debugPrint('[Uploader] $errorMsg');
      return UploadResult.failure(errorMessage: errorMsg);
    } catch (e) {
      final errorMsg = 'Changeset creation failed with unexpected error: $e';
      debugPrint('[Uploader] $errorMsg');
      return UploadResult.failure(errorMessage: errorMsg);
    }
  }

  // Perform node operation (step 2 of 3) 
  Future<UploadResult> performNodeOperation(PendingUpload p, String changesetId) async {
    try {
      debugPrint('[Uploader] Performing ${p.operation.name} operation with changeset $changesetId');
      
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
          <node changeset="$changesetId" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            $tagsXml
          </node>
        </osm>''';
          debugPrint('[Uploader] Creating new node...');
          nodeResp = await _put('/api/0.6/node/create', nodeXml);
          nodeId = nodeResp.body.trim();
          break;

        case UploadOperation.modify:
          // First, fetch the current node to get its version
          debugPrint('[Uploader] Fetching current node ${p.originalNodeId} to get version...');
          final currentNodeResp = await _get('/api/0.6/node/${p.originalNodeId}');
          debugPrint('[Uploader] Current node response: ${currentNodeResp.statusCode}');
          if (currentNodeResp.statusCode != 200) {
            final errorMsg = 'Failed to fetch node ${p.originalNodeId}: HTTP ${currentNodeResp.statusCode} - ${currentNodeResp.body}';
            debugPrint('[Uploader] $errorMsg');
            return UploadResult.failure(errorMessage: errorMsg, changesetId: changesetId);
          }
          
          // Parse version from the response XML
          final currentNodeXml = currentNodeResp.body;
          final versionMatch = RegExp(r'version="(\d+)"').firstMatch(currentNodeXml);
          if (versionMatch == null) {
            final errorMsg = 'Could not parse version from node XML: ${currentNodeXml.length > 200 ? '${currentNodeXml.substring(0, 200)}...' : currentNodeXml}';
            debugPrint('[Uploader] $errorMsg');
            return UploadResult.failure(errorMessage: errorMsg, changesetId: changesetId);
          }
          final currentVersion = versionMatch.group(1)!;
          debugPrint('[Uploader] Current node version: $currentVersion');
          
          // Update existing node with version
          final mergedTags = p.getCombinedTags();
          final tagsXml = mergedTags.entries.map((e) =>
            '<tag k="${e.key}" v="${e.value}"/>').join('\n            ');
          final nodeXml = '''
        <osm>
          <node changeset="$changesetId" id="${p.originalNodeId}" version="$currentVersion" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            $tagsXml
          </node>
        </osm>''';
          debugPrint('[Uploader] Updating node ${p.originalNodeId}...');
          nodeResp = await _put('/api/0.6/node/${p.originalNodeId}', nodeXml);
          nodeId = p.originalNodeId.toString();
          break;

        case UploadOperation.delete:
          // First, fetch the current node to get its version
          debugPrint('[Uploader] Fetching current node ${p.originalNodeId} for deletion...');
          final currentNodeResp = await _get('/api/0.6/node/${p.originalNodeId}');
          debugPrint('[Uploader] Current node response: ${currentNodeResp.statusCode}');
          if (currentNodeResp.statusCode != 200) {
            final errorMsg = 'Failed to fetch node ${p.originalNodeId} for deletion: HTTP ${currentNodeResp.statusCode} - ${currentNodeResp.body}';
            debugPrint('[Uploader] $errorMsg');
            return UploadResult.failure(errorMessage: errorMsg, changesetId: changesetId);
          }
          
          // Parse version from the response XML  
          final currentNodeXml = currentNodeResp.body;
          final versionMatch = RegExp(r'version="(\d+)"').firstMatch(currentNodeXml);
          if (versionMatch == null) {
            final errorMsg = 'Could not parse version from node XML for deletion: ${currentNodeXml.length > 200 ? '${currentNodeXml.substring(0, 200)}...' : currentNodeXml}';
            debugPrint('[Uploader] $errorMsg');
            return UploadResult.failure(errorMessage: errorMsg, changesetId: changesetId);
          }
          final currentVersion = versionMatch.group(1)!;
          debugPrint('[Uploader] Current node version: $currentVersion');
          
          // Delete node - OSM requires current coordinates but empty tags
          final nodeXml = '''
        <osm>
          <node changeset="$changesetId" id="${p.originalNodeId}" version="$currentVersion" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
          </node>
        </osm>''';
          debugPrint('[Uploader] Deleting node ${p.originalNodeId}...');
          nodeResp = await _delete('/api/0.6/node/${p.originalNodeId}', nodeXml);
          nodeId = p.originalNodeId.toString();
          break;

        case UploadOperation.extract:
          // Extract creates a new node with tags from the original node
          final mergedTags = p.getCombinedTags();
          final tagsXml = mergedTags.entries.map((e) =>
            '<tag k="${e.key}" v="${e.value}"/>').join('\n            ');
          final nodeXml = '''
        <osm>
          <node changeset="$changesetId" lat="${p.coord.latitude}" lon="${p.coord.longitude}">
            $tagsXml
          </node>
        </osm>''';
          debugPrint('[Uploader] Extracting node from ${p.originalNodeId} to create new node...');
          nodeResp = await _put('/api/0.6/node/create', nodeXml);
          nodeId = nodeResp.body.trim();
          break;
      }
      
      debugPrint('[Uploader] Node response: ${nodeResp.statusCode} - ${nodeResp.body}');
      if (nodeResp.statusCode != 200) {
        final errorMsg = 'Failed to ${p.operation.name} node: HTTP ${nodeResp.statusCode} - ${nodeResp.body}';
        debugPrint('[Uploader] $errorMsg');
        // Note: changeset is included so caller knows to close it
        return UploadResult.failure(errorMessage: errorMsg, changesetId: changesetId);
      }
      
      final nodeIdInt = int.parse(nodeId);
      debugPrint('[Uploader] ${p.operation.name.capitalize()} node ID: $nodeIdInt');
      
      // Notify success callback for immediate UI feedback
      onSuccess(nodeIdInt);
      
      return UploadResult.success(nodeId: nodeIdInt);
      
    } on TimeoutException catch (e) {
      final errorMsg = 'Node operation timed out after ${kUploadHttpTimeout.inSeconds}s: $e';
      debugPrint('[Uploader] $errorMsg');
      return UploadResult.failure(errorMessage: errorMsg, changesetId: changesetId);
    } catch (e) {
      final errorMsg = 'Node operation failed with unexpected error: $e';
      debugPrint('[Uploader] $errorMsg');
      return UploadResult.failure(errorMessage: errorMsg, changesetId: changesetId);
    }
  }

  // Close changeset (step 3 of 3)
  Future<UploadResult> closeChangeset(String changesetId) async {
    try {
      debugPrint('[Uploader] Closing changeset $changesetId...');
      final closeResp = await _put('/api/0.6/changeset/$changesetId/close', '');
      debugPrint('[Uploader] Close response: ${closeResp.statusCode} - ${closeResp.body}');
      
      switch (closeResp.statusCode) {
        case 200:
          debugPrint('[Uploader] Changeset closed successfully');
          return UploadResult.success();
          
        case 409:
          // Conflict - check if changeset is already closed
          if (closeResp.body.toLowerCase().contains('already closed') ||
              closeResp.body.toLowerCase().contains('closed at')) {
            debugPrint('[Uploader] Changeset already closed');
            return UploadResult.success();
          } else {
            // Other conflict - keep retrying
            final errorMsg = 'Changeset close conflict: HTTP ${closeResp.statusCode} - ${closeResp.body}';
            return UploadResult.failure(errorMessage: errorMsg);
          }
          
        case 404:
          // Changeset not found - this suggests the upload may not have worked
          debugPrint('[Uploader] Changeset not found - marking for full retry');
          return UploadResult.failure(
            errorMessage: 'Changeset not found: HTTP 404',
            changesetNotFound: true,
          );
          
        default:
          // Other errors - keep retrying
          final errorMsg = 'Failed to close changeset $changesetId: HTTP ${closeResp.statusCode} - ${closeResp.body}';
          return UploadResult.failure(errorMessage: errorMsg);
      }
    } on TimeoutException catch (e) {
      final errorMsg = 'Changeset close timed out after ${kUploadHttpTimeout.inSeconds}s: $e';
      return UploadResult.failure(errorMessage: errorMsg);
    } catch (e) {
      final errorMsg = 'Changeset close failed with unexpected error: $e';
      return UploadResult.failure(errorMessage: errorMsg);
    }
  }

  // Legacy full upload method (primarily for simulate mode compatibility)
  Future<UploadResult> upload(PendingUpload p) async {
    debugPrint('[Uploader] Starting full upload for ${p.operation.name} at ${p.coord.latitude}, ${p.coord.longitude}');
    
    // Step 1: Create changeset
    final createResult = await createChangeset(p);
    if (!createResult.success) {
      onError(createResult.errorMessage!);
      return createResult;
    }
    
    final changesetId = createResult.changesetId!;
    
    // Step 2: Perform node operation
    final nodeResult = await performNodeOperation(p, changesetId);
    if (!nodeResult.success) {
      onError(nodeResult.errorMessage!);
      // Note: nodeResult includes changesetId for caller to close if needed
      return nodeResult;
    }
    
    // Step 3: Close changeset
    final closeResult = await closeChangeset(changesetId);
    if (!closeResult.success) {
      // Node operation succeeded but changeset close failed
      // Don't call onError since node operation worked
      debugPrint('[Uploader] Node operation succeeded but changeset close failed');
      return UploadResult.failure(
        errorMessage: closeResult.errorMessage,
        changesetNotFound: closeResult.changesetNotFound,
        changesetId: changesetId,
        nodeId: nodeResult.nodeId,
      );
    }
    
    // All steps successful
    debugPrint('[Uploader] Full upload completed successfully');
    return UploadResult.success(
      changesetId: changesetId,
      nodeId: nodeResult.nodeId,
    );
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
      ).timeout(kUploadHttpTimeout);

  Future<http.Response> _put(String path, String body) => http.put(
        Uri.https(_host, path),
        headers: _headers,
        body: body,
      ).timeout(kUploadHttpTimeout);

  Future<http.Response> _delete(String path, String body) => http.delete(
        Uri.https(_host, path),
        headers: _headers,
        body: body,
      ).timeout(kUploadHttpTimeout);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'text/xml',
      };

  /// Sanitize text for safe inclusion in XML attributes and content
  /// Removes or escapes characters that could break XML parsing
  String _sanitizeXmlText(String input) {
    return input
        .replaceAll('&', '&amp;')   // Must be first to avoid double-escaping
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;')
        .replaceAll('\n', ' ')      // Replace newlines with spaces
        .replaceAll('\r', ' ')      // Replace carriage returns with spaces  
        .replaceAll('\t', ' ')      // Replace tabs with spaces
        .trim();                    // Remove leading/trailing whitespace
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
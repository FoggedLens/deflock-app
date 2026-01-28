import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/node_profile.dart';

class ProfileImportService {
  // Maximum size for base64 encoded profile data (approx 50KB decoded)
  static const int maxBase64Length = 70000;
  
  /// Parse and validate a profile from a base64-encoded JSON string
  /// Returns null if parsing/validation fails
  static NodeProfile? parseProfileFromBase64(String base64Data) {
    try {
      // Basic size validation before expensive decode
      if (base64Data.length > maxBase64Length) {
        debugPrint('[ProfileImportService] Base64 data too large: ${base64Data.length} characters');
        return null;
      }

      // Decode base64
      final jsonBytes = base64Decode(base64Data);
      final jsonString = utf8.decode(jsonBytes);
      
      // Parse JSON
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Validate and sanitize the profile data
      final sanitizedProfile = _validateAndSanitizeProfile(jsonData);
      return sanitizedProfile;
      
    } catch (e) {
      debugPrint('[ProfileImportService] Failed to parse profile from base64: $e');
      return null;
    }
  }
  
  /// Validate profile structure and sanitize all string values
  static NodeProfile? _validateAndSanitizeProfile(Map<String, dynamic> data) {
    try {
      // Extract and sanitize required fields
      final name = _sanitizeString(data['name']);
      if (name == null || name.isEmpty) {
        debugPrint('[ProfileImportService] Profile name is required');
        return null;
      }
      
      // Extract and sanitize tags
      final tagsData = data['tags'];
      if (tagsData is! Map<String, dynamic>) {
        debugPrint('[ProfileImportService] Profile tags must be a map');
        return null;
      }
      
      final sanitizedTags = <String, String>{};
      for (final entry in tagsData.entries) {
        final key = _sanitizeString(entry.key);
        final value = _sanitizeString(entry.value);
        
        if (key != null && key.isNotEmpty) {
          // Allow empty values for refinement purposes
          sanitizedTags[key] = value ?? '';
        }
      }
      
      if (sanitizedTags.isEmpty) {
        debugPrint('[ProfileImportService] Profile must have at least one valid tag');
        return null;
      }
      
      // Extract optional fields with defaults
      final requiresDirection = data['requiresDirection'] ?? true;
      final submittable = data['submittable'] ?? true;
      
      // Parse FOV if provided
      double? fov;
      if (data['fov'] != null) {
        if (data['fov'] is num) {
          final fovValue = (data['fov'] as num).toDouble();
          if (fovValue > 0 && fovValue <= 360) {
            fov = fovValue;
          }
        }
      }
      
      return NodeProfile(
        id: const Uuid().v4(), // Always generate new ID for imported profiles
        name: name,
        tags: sanitizedTags,
        builtin: false, // Imported profiles are always custom
        requiresDirection: requiresDirection is bool ? requiresDirection : true,
        submittable: submittable is bool ? submittable : true,
        editable: true, // Imported profiles are always editable
        fov: fov,
      );
      
    } catch (e) {
      debugPrint('[ProfileImportService] Failed to validate profile: $e');
      return null;
    }
  }
  
  /// Sanitize a string value by trimming and removing potentially harmful characters
  static String? _sanitizeString(dynamic value) {
    if (value == null) return null;
    
    final str = value.toString().trim();
    
    // Remove control characters and limit length
    final sanitized = str.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '');
    
    // Limit length to prevent abuse
    const maxLength = 500;
    if (sanitized.length > maxLength) {
      return sanitized.substring(0, maxLength);
    }
    
    return sanitized;
  }
}
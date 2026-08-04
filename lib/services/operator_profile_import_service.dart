import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/operator_profile.dart';

class OperatorProfileImportService {
  // Maximum size for base64 encoded profile data (approx 50KB decoded)
  static const int maxBase64Length = 70000;
  
  /// Parse and validate an operator profile from a base64-encoded JSON string
  /// Returns null if parsing/validation fails
  static OperatorProfile? parseProfileFromBase64(String base64Data) {
    try {
      // Basic size validation before expensive decode
      if (base64Data.length > maxBase64Length) {
        debugPrint('[OperatorProfileImportService] Base64 data too large: ${base64Data.length} characters');
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
      debugPrint('[OperatorProfileImportService] Failed to parse profile from base64: $e');
      return null;
    }
  }
  
  /// Validate operator profile structure and sanitize all string values
  static OperatorProfile? _validateAndSanitizeProfile(Map<String, dynamic> data) {
    try {
      // Extract and sanitize required fields
      final name = _sanitizeString(data['name']);
      if (name == null || name.isEmpty) {
        debugPrint('[OperatorProfileImportService] Operator profile name is required');
        return null;
      }
      
      // Extract and sanitize tags
      final tagsData = data['tags'];
      if (tagsData is! Map<String, dynamic>) {
        debugPrint('[OperatorProfileImportService] Operator profile tags must be a map');
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
        debugPrint('[OperatorProfileImportService] Operator profile must have at least one valid tag');
        return null;
      }
      
      return OperatorProfile(
        id: const Uuid().v4(), // Always generate new ID for imported profiles
        name: name,
        tags: sanitizedTags,
      );
      
    } catch (e) {
      debugPrint('[OperatorProfileImportService] Failed to validate operator profile: $e');
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
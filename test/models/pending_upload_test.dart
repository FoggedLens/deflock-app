import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:deflockapp/models/pending_upload.dart';
import 'package:deflockapp/models/node_profile.dart';
import 'package:deflockapp/state/settings_state.dart';

void main() {
  group('PendingUpload', () {
    test('should serialize and deserialize upload mode correctly', () {
      // Test each upload mode
      final testModes = [
        UploadMode.production,
        UploadMode.sandbox,
        UploadMode.simulate,
      ];

      for (final mode in testModes) {
        final original = PendingUpload(
          coord: LatLng(37.7749, -122.4194),
          direction: 90.0,
          profile: NodeProfile.flock(),
          uploadMode: mode,
        );

        // Serialize to JSON
        final json = original.toJson();
        
        // Deserialize from JSON
        final restored = PendingUpload.fromJson(json);

        // Verify upload mode is preserved
        expect(restored.uploadMode, equals(mode));
        expect(restored.uploadModeDisplayName, equals(original.uploadModeDisplayName));
        
        // Verify other fields too
        expect(restored.coord.latitude, equals(original.coord.latitude));
        expect(restored.coord.longitude, equals(original.coord.longitude));
        expect(restored.direction, equals(original.direction));
        expect(restored.profile.id, equals(original.profile.id));
      }
    });

    test('should handle legacy JSON without uploadMode', () {
      // Simulate old JSON format without uploadMode field
      final legacyJson = {
        'lat': 37.7749,
        'lon': -122.4194,
        'dir': 90.0,
        'profile': NodeProfile.flock().toJson(),
        'originalNodeId': null,
        'attempts': 0,
        'error': false,
        // Note: no 'uploadMode' field
      };

      final upload = PendingUpload.fromJson(legacyJson);
      
      // Should default to production mode for legacy entries
      expect(upload.uploadMode, equals(UploadMode.production));
      expect(upload.uploadModeDisplayName, equals('Production'));
    });

    test('should correctly identify edits vs new cameras', () {
      final newCamera = PendingUpload(
        coord: LatLng(37.7749, -122.4194),
        direction: 90.0,
        profile: NodeProfile.flock(),
        uploadMode: UploadMode.production,
      );

      final editCamera = PendingUpload(
        coord: LatLng(37.7749, -122.4194),
        direction: 90.0,
        profile: CameraProfile.flock(),
        uploadMode: UploadMode.production,
        originalNodeId: 12345,
      );

      expect(newCamera.isEdit, isFalse);
      expect(editCamera.isEdit, isTrue);
    });
  });
}
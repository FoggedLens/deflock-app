import '../models/pending_upload.dart';
import '../state/session_state.dart';
import '../state/settings_state.dart';
import 'direction_submission_formatter.dart';

/// Detects whether an edit would serialize to a different OSM node.
class EditNodeChangeDetector {
  const EditNodeChangeDetector._();

  static bool hasActualChanges(EditNodeSession session) {
    if (session.extractFromWay) return true;

    const tolerance = 0.0000001;
    if ((session.target.latitude - session.originalNode.coord.latitude).abs() >
            tolerance ||
        (session.target.longitude - session.originalNode.coord.longitude)
                .abs() >
            tolerance) {
      return true;
    }

    final originalTags = session.originalNode.tags;
    final submittedTags = _getSubmittedTags(session);

    final originalDirection = _directionValue(originalTags);
    final submittedDirection =
        originalDirection == null && session.directions.isEmpty
        ? null
        : _directionValue(submittedTags);
    if (originalDirection != submittedDirection) {
      return true;
    }

    return !_tagsEqual(originalTags, submittedTags);
  }

  static Map<String, String> _getSubmittedTags(EditNodeSession session) {
    if (session.profile == null) return <String, String>{};

    return PendingUpload(
      coord: session.target,
      direction: DirectionSubmissionFormatter.format(
        session.directions,
        session.profile,
      ),
      profile: session.profile,
      operatorProfile: session.operatorProfile,
      refinedTags: session.refinedTags,
      additionalExistingTags: session.additionalExistingTags,
      changesetComment: session.changesetComment,
      uploadMode: UploadMode.production,
      operation: UploadOperation.modify,
      originalNodeId: session.originalNode.id,
    ).getCombinedTags();
  }

  static String? _directionValue(Map<String, String> tags) =>
      tags['direction'] ?? tags['camera:direction'];

  static bool _tagsEqual(
    Map<String, String> originalTags,
    Map<String, String> submittedTags,
  ) {
    final original = Map<String, String>.from(originalTags)
      ..remove('direction')
      ..remove('camera:direction');
    final submitted = Map<String, String>.from(submittedTags)
      ..remove('direction')
      ..remove('camera:direction');

    if (original.length != submitted.length) return false;
    for (final entry in original.entries) {
      if (submitted[entry.key] != entry.value) return false;
    }
    return true;
  }
}

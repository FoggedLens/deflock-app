import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:collection/collection.dart';
import '../models/osm_node.dart';
import '../models/pending_upload.dart';
import '../services/map_data_provider.dart';
import '../app_state.dart';
import '../services/localization_service.dart';
import '../dev_config.dart';
import 'advanced_edit_options_sheet.dart';


class NodeTagSheet extends StatefulWidget {
  final OsmNode node;
  final VoidCallback? onEditPressed;
  final bool isNodeLimitActive;

  const NodeTagSheet({
    super.key,
    required this.node,
    this.onEditPressed,
    this.isNodeLimitActive = false,
  });

  @override
  State<NodeTagSheet> createState() => _NodeTagSheetState();
}

class _NodeTagSheetState extends State<NodeTagSheet> {
  // The PendingUpload backing this node (if it was in a pending state when the
  // sheet was opened). We resolve this once and hold onto the object reference
  // itself (not just its id) so we can keep observing its live status via its
  // mutable fields even after it's eventually removed from the queue list
  // (which happens ~1s after completion). Without this, once the item left
  // the queue we'd have no way to tell "finished successfully" apart from
  // "still pending" and would show stale/misleading status forever.
  PendingUpload? _upload;
  bool _uploadResolved = false;

  @override
  void initState() {
    super.initState();
    _resolveTrackedUpload();
  }

  void _resolveTrackedUpload() {
    if (_uploadResolved) return;
    _uploadResolved = true;

    final appState = context.read<AppState>();
    if (widget.node.tags['_pending_upload'] == 'true') {
      _upload = appState.pendingUploads
          .firstWhereOrNull((u) => u.tempNodeId == widget.node.id);
    } else if (widget.node.tags['_pending_edit'] == 'true' ||
        widget.node.tags['_pending_deletion'] == 'true') {
      _upload = appState.pendingUploads
          .firstWhereOrNull((u) => u.originalNodeId == widget.node.id);
    }
  }

  /// Resolve the node data that should currently be displayed.
  ///
  /// While an upload/edit/deletion is still in progress (or has failed), this
  /// is just the snapshot that was passed in when the sheet was opened -
  /// nothing has changed in the cache yet. Once the tracked upload completes,
  /// we switch to the live node from the cache using the *real* submitted ID
  /// (which can differ from the temporary negative "-epoch" ID for creates
  /// and extracts, but matches the original ID for edits) so that tags, id,
  /// and editability reflect reality instead of the stale pre-submission
  /// snapshot. Returns null if the node has been deleted.
  OsmNode? _resolveDisplayNode() {
    final upload = _upload;
    if (upload == null) {
      // No tracked upload - either this node was never pending, or we
      // couldn't find a matching queue entry (shouldn't normally happen).
      // Try a live cache lookup so we still pick up any external updates,
      // but fall back to the passed-in node if it's not (or no longer) cached.
      return MapDataProvider().getNodeById(widget.node.id) ?? widget.node;
    }

    if (!upload.isComplete) {
      // Still pending/in-progress/failed - nothing has changed yet.
      return widget.node;
    }

    if (upload.isDeletion) {
      return null; // Node has been deleted
    }

    // Upload completed successfully (create/modify/extract). Look up the
    // live node using the real submitted ID (same as originalNodeId for
    // modify operations, a brand-new positive ID for create/extract).
    final realId = upload.submittedNodeId ?? widget.node.id;
    final cached = MapDataProvider().getNodeById(realId);
    if (cached != null) return cached;

    // Fallback: cache might have already been cleared/replaced; reconstruct
    // from the upload data directly so we don't fall back to stale pending
    // tags/id.
    return OsmNode(
      id: realId,
      coord: upload.coord,
      tags: upload.getCombinedTags(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocalizationService.instance,
      builder: (context, child) {
        final appState = context.watch<AppState>();
        final locService = LocalizationService.instance;

        final upload = _upload;
        final isDeleted = upload != null && upload.isComplete && upload.isDeletion;
        final displayNode = isDeleted ? null : _resolveDisplayNode();

        if (displayNode == null) {
          return _buildDeletedSheet(context, locService);
        }

        // Check if this device is editable (not a pending upload, pending edit, or pending deletion)
        final isEditable = (!displayNode.tags.containsKey('_pending_upload') || 
                           displayNode.tags['_pending_upload'] != 'true') &&
                          (!displayNode.tags.containsKey('_pending_edit') || 
                           displayNode.tags['_pending_edit'] != 'true') &&
                          (!displayNode.tags.containsKey('_pending_deletion') || 
                           displayNode.tags['_pending_deletion'] != 'true');
        
        // Check if this is a real OSM node (not pending) - for "View on OSM" button
        final isRealOSMNode = !displayNode.tags.containsKey('_pending_upload') &&
                              displayNode.id > 0; // Real OSM nodes have positive IDs
        
        void openEditSheet() {
          // Check if node limit is active and warn user
          if (widget.isNodeLimitActive) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  locService.t('nodeLimitIndicator.editingDisabledMessage'),
                ),
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }
          
          if (widget.onEditPressed != null) {
            widget.onEditPressed!(); // Use callback if provided
          } else {
            // Fallback behavior
            Navigator.pop(context); // Close this sheet first
            appState.startEditSession(displayNode); // HomeScreen will auto-show the edit sheet
          }
        }

        void verifyNode() {
          Navigator.pop(context); // Close this sheet first
          appState.verifyNode(node);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(locService.t('node.verifyQueuedForUpload'))),
          );
        }

        void deleteNode() async {
          if (!appState.isLoggedIn) {
            final shouldLogIn = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: Text(locService.t('node.confirmDeleteTitle')),
                content: Text(locService.t('node.mustBeLoggedInToDelete')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(locService.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(locService.t('actions.logIn')),
                  ),
                ],
              ),
            );

            if ((shouldLogIn ?? false) && context.mounted) {
              Navigator.pushNamed(context, '/settings/osm-account');
            }
            return;
          }

          final result = await showDialog<({bool confirmed, String comment})>(
            context: context,
            builder: (BuildContext context) => _DeleteNodeDialog(
              nodeId: displayNode.id.toString(),
              locService: locService,
            ),
          );

          if ((result?.confirmed ?? false) && context.mounted) {
            Navigator.pop(context); // Close this sheet first
            appState.deleteNode(displayNode, changesetComment: result!.comment);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(locService.t('node.deleteQueuedForUpload')),
              ),
            );
          }
        }

        void viewOnOSM() async {
          final url = 'https://www.openstreetmap.org/node/${displayNode.id}';
          try {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      locService.t('advancedEdit.couldNotOpenOSMWebsite'),
                    ),
                  ),
                );
              }
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    locService.t('advancedEdit.couldNotOpenOSMWebsite'),
                  ),
                ),
              );
            }
          }
        }

        void openAdvancedEdit() {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => AdvancedEditOptionsSheet(node: displayNode),
          );
        }

        void viewInQueue() {
          Navigator.pop(context); // Close this sheet first
          Navigator.pushNamed(context, '/settings/queue');
        }

        Widget? uploadStatusBanner;
        if (!isEditable) {
          final IconData statusIcon;
          final Color statusColor;
          final String statusLabel;
          final bool showSpinner;
          final bool showQueueButton;

          final state = upload?.uploadState;

          if (state == null) {
            // Fallback: tag says pending but we couldn't find a matching
            // queue entry (shouldn't normally happen).
            statusIcon = Icons.hourglass_empty;
            statusColor = Colors.orange;
            statusLabel = locService.t('node.uploadPending');
            showSpinner = false;
            showQueueButton = true;
          } else {
            switch (state) {
              case UploadState.pending:
                statusIcon = Icons.hourglass_empty;
                statusColor = Colors.orange;
                statusLabel = locService.t('node.uploadPending');
                showSpinner = false;
                showQueueButton = true;
                break;
              case UploadState.creatingChangeset:
                statusIcon = Icons.cloud_upload_outlined;
                statusColor = Colors.orange;
                statusLabel = locService.t('node.uploadCreatingChangeset');
                showSpinner = true;
                showQueueButton = true;
                break;
              case UploadState.uploading:
                statusIcon = Icons.cloud_upload_outlined;
                statusColor = Colors.orange;
                statusLabel = locService.t('node.uploadUploading');
                showSpinner = true;
                showQueueButton = true;
                break;
              case UploadState.closingChangeset:
                statusIcon = Icons.cloud_upload_outlined;
                statusColor = Colors.orange;
                statusLabel = locService.t('node.uploadClosingChangeset');
                showSpinner = true;
                showQueueButton = true;
                break;
              case UploadState.error:
                statusIcon = Icons.error_outline;
                statusColor = Colors.red;
                statusLabel = locService.t('node.uploadError');
                showSpinner = false;
                showQueueButton = true;
                break;
              case UploadState.complete:
                statusIcon = Icons.check_circle_outline;
                statusColor = Colors.green;
                statusLabel = locService.t('node.uploadComplete');
                showSpinner = false;
                showQueueButton = false;
                break;
            }
          }

          uploadStatusBanner = Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              border: Border.all(color: statusColor.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (showSpinner)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor,
                        ),
                      )
                    else
                      Icon(statusIcon, color: statusColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (state == UploadState.error &&
                    (upload?.errorMessage?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    upload!.errorMessage!,
                    style: TextStyle(
                      color: statusColor.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (showQueueButton) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: viewInQueue,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 28),
                        foregroundColor: statusColor,
                      ),
                      child: Text(locService.t('node.viewInQueue')),
                    ),
                  ),
                ],
              ],
            ),
          );
        }


        return LayoutBuilder(
          builder: (context, constraints) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  locService.t('node.title').replaceAll('{}', displayNode.id.toString()),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),

                ?uploadStatusBanner,

                // Tag list with flexible height constraint

                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * getTagListHeightRatio(context),
                  ),
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...displayNode.tags.entries
                              .where((e) => !e.key.startsWith('_')) // Hide internal bookkeeping tags
                              .map(
                            (e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.key,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Linkify(
                                      onOpen: (link) async {
                                        final uri = Uri.parse(link.url);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        } else if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('${LocalizationService.instance.t('advancedEdit.couldNotOpenURL')}: ${link.url}')),
                                          );
                                        }
                                      },
                                      text: e.value,
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                      ),
                                      linkStyle: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                      ),
                                      options: const LinkifyOptions(humanize: false),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        ],
                      ),
                    ),
                  ),
                ),


                const SizedBox(height: 16),
                // First row: View and Advanced buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isRealOSMNode) ...[
                      OutlinedButton.icon(
                        onPressed: () => viewOnOSM(),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(locService.t('actions.viewOnOSM')),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    if (isEditable) ...[
                      OutlinedButton.icon(
                        onPressed: openAdvancedEdit,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(locService.t('actions.advanced')),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                // Second row: Edit, Delete, and Close buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isEditable) ...[
                      ElevatedButton.icon(
                        onPressed: openEditSheet,
                        icon: const Icon(Icons.edit, size: 18),
                        label: Text(locService.edit),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: displayNode.isConstrained ? null : deleteNode,
                        icon: const Icon(Icons.delete, size: 18),
                        label: Text(locService.t('actions.delete')),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          foregroundColor: displayNode.isConstrained ? null : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(locService.t('actions.close')),
                    ),
                  ],
                ),
              ],
              ),
              ),
            );
          },
        );
      },
    );
  }

  /// Shown when the tracked upload was a deletion that has now completed -
  /// the underlying node no longer exists, so we can't show tags or offer
  /// edit/delete actions on it anymore.
  Widget _buildDeletedSheet(BuildContext context, LocalizationService locService) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locService.t('node.title').replaceAll('{}', widget.node.id.toString()),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      locService.t('node.deletedSuccessfully'),
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(locService.t('actions.close')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _DeleteReason {
  deviceRemoved,
  duplicateNode,
  misidentifiedInfra,
  spamVandalism,
  custom,
}

extension _DeleteReasonLabel on _DeleteReason {
  String label(LocalizationService locService) {
    switch (this) {
      case _DeleteReason.deviceRemoved:
        return locService.t('node.deleteReasonDeviceRemoved');
      case _DeleteReason.duplicateNode:
        return locService.t('node.deleteReasonDuplicateNode');
      case _DeleteReason.misidentifiedInfra:
        return locService.t('node.deleteReasonMisidentifiedInfra');
      case _DeleteReason.spamVandalism:
        return locService.t('node.deleteReasonSpamVandalism');
      case _DeleteReason.custom:
        return locService.t('node.deleteReasonCustom');
    }
  }

  /// The text used to build the changeset comment (kept in English/consistent
  /// regardless of UI language, matching prior app behavior for uploads).
  String get commentText {
    switch (this) {
      case _DeleteReason.deviceRemoved:
        return 'device removed';
      case _DeleteReason.duplicateNode:
        return 'duplicate node';
      case _DeleteReason.misidentifiedInfra:
        return 'misidentified infra';
      case _DeleteReason.spamVandalism:
        return 'spam/vandalism';
      case _DeleteReason.custom:
        return '';
    }
  }
}

class _DeleteNodeDialog extends StatefulWidget {
  final String nodeId;
  final LocalizationService locService;

  const _DeleteNodeDialog({required this.nodeId, required this.locService});

  @override
  State<_DeleteNodeDialog> createState() => _DeleteNodeDialogState();
}

class _DeleteNodeDialogState extends State<_DeleteNodeDialog> {
  late final TextEditingController _commentController;
  _DeleteReason? _selectedReason;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_selectedReason == null) return false;
    if (_selectedReason == _DeleteReason.custom) {
      return _commentController.text.trim().isNotEmpty;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.locService.t('node.confirmDeleteTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.locService.t(
              'node.confirmDeleteMessage',
              params: [widget.nodeId],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.locService.t('node.deleteReasonLabel'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<_DeleteReason>(
            initialValue: _selectedReason,
            hint: Text(widget.locService.t('node.deleteReasonSelectHint')),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: _DeleteReason.values
                .map((reason) => DropdownMenuItem(
                      value: reason,
                      child: Text(reason.label(widget.locService)),
                    ))
                .toList(),
            onChanged: (reason) {
              setState(() {
                _selectedReason = reason;
              });
            },
          ),
          if (_selectedReason == _DeleteReason.custom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: widget.locService.t('node.deleteReasonHint'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop((confirmed: false, comment: '')),
          child: Text(widget.locService.cancel),
        ),
        TextButton(
          onPressed: _canConfirm
              ? () {
                  final reasonText = _selectedReason == _DeleteReason.custom
                      ? _commentController.text.trim()
                      : _selectedReason!.commentText;
                  final finalComment = reasonText.isEmpty
                      ? 'Delete a surveillance node'
                      : 'Delete a surveillance node: $reasonText';
                  Navigator.of(context).pop((confirmed: true, comment: finalComment));
                }
              : null,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: Text(widget.locService.t('actions.delete')),
        ),
      ],
    );
  }
}

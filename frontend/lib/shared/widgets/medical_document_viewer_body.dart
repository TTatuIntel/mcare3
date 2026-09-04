import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/env/app_env.dart';
import '../models/document.dart';
import '../services/document_opener.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'document_action_bar.dart';
import 'app_dialog.dart';
import 'app_icons.dart';
import 'app_toast.dart';
import 'document_preview_panel.dart';

/// Shared document viewer body — preview, metadata, download, delete.
class MedicalDocumentViewerBody extends StatefulWidget {
  const MedicalDocumentViewerBody({
    super.key,
    required this.documentId,
    required this.fileType,
    required this.metaRows,
    this.documentTitle = 'document',
    this.mimeType,
    this.downloadName,
    this.patientUserId,
    this.hasFile = true,
    this.onDelete,
    this.onEdit,
    this.previewHeight = 300,
    this.previewReloadToken = 0,
    this.footer,
  });

  final String documentId;
  final DocumentFileType fileType;

  /// Names the file handed to the browser or the share sheet. A PDF arriving
  /// as an extensionless temp name opens in nothing.
  final String documentTitle;

  /// What the server recorded the stored file to be, and what it should be
  /// saved as. Without these the type is guessed from [fileType], which files
  /// every issued report under `application/octet-stream` named `.bin`.
  final String? mimeType;
  final String? downloadName;

  final List<Widget> metaRows;
  final String? patientUserId;
  final bool hasFile;
  final Future<void> Function()? onDelete;
  final VoidCallback? onEdit;
  final double previewHeight;
  final int previewReloadToken;

  /// Rendered under the action bar. Carries the actions that are about the
  /// record rather than the file — asking staff to remove a document the
  /// patient cannot delete themselves, and the answer when they refuse.
  final Widget? footer;

  @override
  State<MedicalDocumentViewerBody> createState() =>
      _MedicalDocumentViewerBodyState();
}

class _MedicalDocumentViewerBodyState extends State<MedicalDocumentViewerBody> {
  bool _downloading = false;
  bool _deleting = false;
  bool _viewing = false;

  /// Fetches the bytes once and hands them to the platform, either to display
  /// or to save. One call site for both so the two actions cannot drift apart
  /// again in what they ask the server for.
  Future<bool> _fetchAndHandOver({required bool save}) {
    return DocumentOpener.open(
      documentId: widget.documentId,
      fileType: widget.fileType,
      title: widget.documentTitle,
      patientUserId: widget.patientUserId,
      mimeType: widget.mimeType,
      downloadName: widget.downloadName,
      save: save,
    );
  }

  /// Opens the file the way the current platform can: a browser tab on web,
  /// the system share sheet ("Open in…", Files, Books, print) on iOS and
  /// Android.
  Future<void> _view() async {
    if (!widget.hasFile) {
      AppToast.warn(context, 'No file attached. Use Edit to upload a file.');
      return;
    }
    setState(() => _viewing = true);
    try {
      final opened = await _fetchAndHandOver(save: false);
      if (!mounted) return;
      if (!opened) {
        AppToast.warn(context, 'This file could not be opened.');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.warn(context, 'Could not open file: $e');
    } finally {
      if (mounted) setState(() => _viewing = false);
    }
  }

  /// Puts the file on the reader's device.
  ///
  /// This used to be [_view] under another name — the same call, the same
  /// `inline` response, the same new tab. A patient at a hospital reception
  /// tapping Download got a tab they could not hand over and no file. On web
  /// it now writes to their Downloads folder; on a phone the share sheet is
  /// where Save to Files lives, so that is still the right destination.
  Future<void> _download() async {
    if (!widget.hasFile) {
      AppToast.warn(context, 'No file attached. Use Edit to upload a file.');
      return;
    }
    setState(() => _downloading = true);
    try {
      final saved = await _fetchAndHandOver(save: AppEnv.backendEnabled);
      if (!mounted) return;
      if (saved) {
        AppToast.success(
          context,
          kIsWeb ? 'Saved to your downloads.' : 'Choose where to save it…',
        );
      } else {
        AppToast.warn(context, 'This file could not be downloaded.');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.warn(context, 'Could not download: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _delete() async {
    if (widget.onDelete == null) return;
    final ok = await AppDialog.confirm(
      context,
      title: 'Delete document?',
      message: 'This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
      icon: AppIcons.delete,
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await widget.onDelete!();
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(context, 'Document deleted.');
    } catch (e) {
      if (!mounted) return;
      AppToast.warn(context, 'Could not delete: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DocumentPreviewPanel(
          documentId: widget.documentId,
          fileType: widget.fileType,
          mimeType: widget.mimeType,
          patientUserId: widget.patientUserId,
          hasFile: widget.hasFile,
          height: widget.previewHeight,
          reloadToken: widget.previewReloadToken,
        ),
        const SizedBox(height: AppSpacing.lg),
        ...widget.metaRows,
        const SizedBox(height: AppSpacing.lg),
        DocumentActionBar(
          onView: _view,
          onDownload: _download,
          onEdit: widget.onEdit,
          onDelete: widget.onDelete != null ? _delete : null,
          viewLoading: _viewing,
          downloadLoading: _downloading,
          deleteLoading: _deleting,
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: AppSpacing.lg),
          widget.footer!,
        ],
      ],
    );
  }
}

/// Simple label/value row for document metadata.
class DocumentMetaRow extends StatelessWidget {
  const DocumentMetaRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

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

  /// Opens the file the way the current platform can: a browser tab on web,
  /// the system share sheet ("Open in…", Files, Books, print) on iOS and
  /// Android. This used to call the web path unconditionally, so every Open
  /// and Download on a phone ended in a stopped spinner and no file.
  Future<void> _openExternal() async {
    if (!widget.hasFile) {
      AppToast.warn(context, 'No file attached. Use Edit to upload a file.');
      return;
    }
    setState(() => _viewing = true);
    try {
      final opened = await DocumentOpener.open(
        documentId: widget.documentId,
        fileType: widget.fileType,
        title: widget.documentTitle,
        patientUserId: widget.patientUserId,
      );
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

  Future<void> _view() => _openExternal();

  Future<void> _download() async {
    if (!widget.hasFile) {
      AppToast.warn(context, 'No file attached. Use Edit to upload a file.');
      return;
    }
    setState(() => _downloading = true);
    try {
      if (!AppEnv.backendEnabled) {
        await _openExternal();
        return;
      }
      final opened = await DocumentOpener.open(
        documentId: widget.documentId,
        fileType: widget.fileType,
        title: widget.documentTitle,
        patientUserId: widget.patientUserId,
      );
      if (!mounted) return;
      if (opened) {
        AppToast.success(context, 'Opening file…');
      } else {
        AppToast.warn(context, 'This file could not be opened.');
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

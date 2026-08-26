import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/web/web_platform.dart' as web_platform;
import '../models/document.dart';
import '../services/document_preview_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';
import 'document_pdf_view_stub.dart'
    if (dart.library.html) 'document_pdf_view_web.dart' as pdf_view;
import 'loading/loading.dart';

/// In-app preview for PDFs and images — authenticated, no public storage URL.
class DocumentPreviewPanel extends StatefulWidget {
  const DocumentPreviewPanel({
    super.key,
    required this.documentId,
    required this.fileType,
    this.patientUserId,
    this.hasFile = true,
    this.height = 280,
    this.reloadToken = 0,
  });

  final String documentId;
  final DocumentFileType fileType;
  final String? patientUserId;
  final bool hasFile;
  final double height;
  final int reloadToken;

  @override
  State<DocumentPreviewPanel> createState() => _DocumentPreviewPanelState();
}

class _DocumentPreviewPanelState extends State<DocumentPreviewPanel> {
  Uint8List? _bytes;
  String? _objectUrl;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(DocumentPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.patientUserId != widget.patientUserId ||
        oldWidget.fileType != widget.fileType ||
        oldWidget.hasFile != widget.hasFile ||
        oldWidget.reloadToken != widget.reloadToken) {
      _load();
    }
  }

  @override
  void dispose() {
    DocumentPreviewService.revokeObjectUrl(_objectUrl);
    super.dispose();
  }

  Future<void> _load() async {
    DocumentPreviewService.revokeObjectUrl(_objectUrl);
    setState(() {
      _loading = true;
      _error = null;
      _bytes = null;
      _objectUrl = null;
    });

    if (!widget.hasFile) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No file attached. Use Edit to upload a file.';
      });
      return;
    }

    try {
      final content = await DocumentPreviewService.resolveContent(
        documentId: widget.documentId,
        fileType: widget.fileType,
        patientUserId: widget.patientUserId,
      );
      if (!mounted) return;
      if (!content.hasData) {
        setState(() {
          _loading = false;
          _error = 'Preview not available for this file.';
        });
        return;
      }
      final url = DocumentPreviewService.objectUrlFor(content);
      setState(() {
        _bytes = content.bytes;
        _objectUrl = url;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('No file attached')
            ? 'No file attached. Use Edit to upload a file.'
            : 'Could not load preview.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: AppPalette.surfaceMuted(context),
          border: Border.all(color: AppPalette.border(context)),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: McareLoadingMark(size: McareMarkSize.small),
      );
    }
    if (_error != null) {
      return _Placeholder(
        icon: AppIcons.alert,
        message: _error!,
        onRetry: _load,
      );
    }

    switch (widget.fileType) {
      case DocumentFileType.image:
        if (_bytes != null) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.memory(
              _bytes!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => _Placeholder(
                icon: AppIcons.image,
                message: 'Image could not be loaded.',
                onRetry: _load,
              ),
            ),
          );
        }
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            _objectUrl!,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _Placeholder(
              icon: AppIcons.image,
              message: 'Image could not be loaded.',
              onRetry: _load,
            ),
          ),
        );
      case DocumentFileType.pdf:
        if (kIsWeb && _objectUrl != null) {
          return pdf_view.buildPdfPreview(
            documentId: widget.documentId,
            url: _objectUrl!,
          );
        }
        return _Placeholder(
          icon: AppIcons.document,
          message: 'PDF preview is available in the browser app.',
          actionLabel: _objectUrl != null ? 'Open PDF' : null,
          onAction: _objectUrl != null
              ? () => web_platform.openWindow(_objectUrl!, '_blank')
              : null,
        );
      case DocumentFileType.doc:
        return _Placeholder(
          icon: AppIcons.document,
          message: 'Word documents open in a new tab.',
          actionLabel: _objectUrl != null ? 'Open file' : null,
          onAction: _objectUrl != null
              ? () => web_platform.openWindow(_objectUrl!, '_blank')
              : null,
        );
      case DocumentFileType.other:
        if (kIsWeb && _objectUrl != null) {
          return pdf_view.buildPdfPreview(
            documentId: widget.documentId,
            url: _objectUrl!,
          );
        }
        return _Placeholder(
          icon: AppIcons.document,
          message: 'Tap View below to open this file.',
          actionLabel: _objectUrl != null ? 'Open file' : null,
          onAction: _objectUrl != null
              ? () => web_platform.openWindow(_objectUrl!, '_blank')
              : null,
        );
    }
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.message,
    this.onRetry,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: AppPalette.textMuted(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

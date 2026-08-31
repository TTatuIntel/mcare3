import 'dart:typed_data';

import '../models/document.dart';
import 'document_preview_service.dart';
import 'document_opener_io.dart'
    if (dart.library.html) 'document_opener_web.dart'
    as impl;

/// Opens a document's bytes in whatever the platform considers a viewer.
///
/// Both halves end at the same place — the file in front of the patient — by
/// routes that have nothing in common: a browser tab for a blob URL on web, the
/// system share sheet on iOS and Android. Keeping that choice behind one call
/// is what stopped the viewer from being written against the web path alone,
/// which is how Open and Download came to do nothing on a phone.
class DocumentOpener {
  DocumentOpener._();

  /// Fetches [documentId] and hands it to the platform viewer.
  ///
  /// Returns false when there was nothing to open, so the caller can say so
  /// rather than leaving the reader looking at a spinner that stopped.
  static Future<bool> open({
    required String documentId,
    required DocumentFileType fileType,
    required String title,
    String? patientUserId,
  }) async {
    final content = await DocumentPreviewService.resolveContent(
      documentId: documentId,
      fileType: fileType,
      patientUserId: patientUserId,
    );

    final bytes = content.bytes;
    if (bytes == null || bytes.isEmpty) {
      // Fixture mode has a URL instead of bytes; the browser can open it
      // directly and native has nothing to hand the share sheet.
      final url = DocumentPreviewService.objectUrlFor(content);
      return url != null && url.isNotEmpty && await _openUrl(url);
    }

    return impl.openDocumentBytes(
      bytes: bytes,
      mimeType: content.mimeType,
      filename: filenameFor(title, fileType),
    );
  }

  static Future<bool> _openUrl(String url) => impl.openDocumentUrl(url);

  /// Opens bytes the caller already holds.
  ///
  /// Used for anything that is not a stored MedicalDocument — chiefly an
  /// issued report, which is rendered on demand from the frozen snapshot
  /// rather than kept as a file.
  static Future<bool> openBytes({
    required Uint8List bytes,
    required String mimeType,
    required String filename,
  }) {
    if (bytes.isEmpty) return Future.value(false);

    return impl.openDocumentBytes(
      bytes: bytes,
      mimeType: mimeType,
      filename: filename,
    );
  }

  /// A filename the receiving app can make sense of. Whatever the patient
  /// called the document, with the extension its type implies — a PDF handed
  /// over as "Blood panel" with no suffix opens in nothing.
  static String filenameFor(String title, DocumentFileType fileType) =>
      filenameWith(title, extensionFor(fileType));

  /// Same, for content whose type is known directly rather than through a
  /// stored document's [DocumentFileType] — an issued report, for instance.
  static String filenameWith(String title, String extension) {
    final base = title
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    final safe = base.isEmpty ? 'document' : base;

    return '$safe.$extension';
  }

  static String extensionFor(DocumentFileType fileType) => switch (fileType) {
    DocumentFileType.pdf => 'pdf',
    DocumentFileType.image => 'jpg',
    DocumentFileType.doc => 'docx',
    DocumentFileType.other => 'bin',
  };
}

/// Re-exported so callers do not need the typed-data import.
typedef DocumentBytes = Uint8List;

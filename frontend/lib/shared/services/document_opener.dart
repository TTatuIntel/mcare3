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
  /// [mimeType] and [downloadName] are what the server recorded for the stored
  /// file. Pass them wherever they are known: without them the type has to be
  /// guessed from [fileType], a four-value enum in which every issued report is
  /// "other" — and "other" meant `application/octet-stream` named `.bin`, which
  /// no browser renders and no phone will open.
  ///
  /// [save] asks for the file to be written to the reader's device rather than
  /// displayed. On the web those are genuinely different acts; on a phone the
  /// share sheet is both, and is where Save to Files lives.
  ///
  /// Returns false when there was nothing to open, so the caller can say so
  /// rather than leaving the reader looking at a spinner that stopped.
  static Future<bool> open({
    required String documentId,
    required DocumentFileType fileType,
    required String title,
    String? patientUserId,
    String? mimeType,
    String? downloadName,
    bool save = false,
  }) async {
    final content = await DocumentPreviewService.resolveContent(
      documentId: documentId,
      fileType: fileType,
      patientUserId: patientUserId,
      mimeType: mimeType,
    );

    final bytes = content.bytes;
    if (bytes == null || bytes.isEmpty) {
      // Fixture mode has a URL instead of bytes; the browser can open it
      // directly and native has nothing to hand the share sheet.
      final url = DocumentPreviewService.objectUrlFor(content);
      return url != null && url.isNotEmpty && await _openUrl(url);
    }

    final filename = resolveFilename(
      downloadName: downloadName,
      title: title,
      mimeType: content.mimeType,
      fileType: fileType,
    );

    if (save) {
      return impl.downloadDocumentBytes(
        bytes: bytes,
        mimeType: content.mimeType,
        filename: filename,
      );
    }

    return impl.openDocumentBytes(
      bytes: bytes,
      mimeType: content.mimeType,
      filename: filename,
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
    bool save = false,
  }) {
    if (bytes.isEmpty) return Future.value(false);

    return save
        ? impl.downloadDocumentBytes(
            bytes: bytes,
            mimeType: mimeType,
            filename: filename,
          )
        : impl.openDocumentBytes(
            bytes: bytes,
            mimeType: mimeType,
            filename: filename,
          );
  }

  /// The name the file should arrive under.
  ///
  /// The server's is authoritative — it is the name the document was uploaded
  /// with, which is what the patient will look for. Everything after it is
  /// fallback for older rows.
  static String resolveFilename({
    String? downloadName,
    required String title,
    String? mimeType,
    required DocumentFileType fileType,
  }) {
    final given = downloadName?.trim() ?? '';
    if (given.isNotEmpty && given.contains('.')) return given;

    final extension =
        extensionForMime(mimeType) ?? extensionFor(fileType);

    return filenameWith(title, extension);
  }

  /// A filename the receiving app can make sense of. Whatever the document was
  /// called, with the extension its type implies — a PDF handed over as "Blood
  /// panel" with no suffix opens in nothing.
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

  /// The extension a content type implies, for naming a file the server
  /// recorded a type for but no filename.
  static String? extensionForMime(String? mimeType) {
    final m = mimeType?.toLowerCase().split(';').first.trim() ?? '';
    return switch (m) {
      'application/pdf' => 'pdf',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      'image/bmp' => 'bmp',
      'image/tiff' => 'tiff',
      'text/html' => 'html',
      'text/plain' => 'txt',
      'text/csv' => 'csv',
      'application/rtf' => 'rtf',
      'application/msword' => 'doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        'docx',
      'application/vnd.oasis.opendocument.text' => 'odt',
      'application/vnd.ms-excel' => 'xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
        'xlsx',
      _ => null,
    };
  }
}

/// Re-exported so callers do not need the typed-data import.
typedef DocumentBytes = Uint8List;

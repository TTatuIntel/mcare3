import 'dart:typed_data';

import '../../core/api/documents_api.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../models/document.dart';
import '../models/user_role.dart';
import 'document_blob_url_stub.dart'
    if (dart.library.html) 'document_blob_url_web.dart'
    as blob_url;

/// Resolved preview payload for in-app document viewing.
class DocumentPreviewContent {
  const DocumentPreviewContent({
    this.bytes,
    this.demoUrl,
    required this.mimeType,
  });

  final Uint8List? bytes;
  final String? demoUrl;
  final String mimeType;

  bool get hasData => bytes != null || (demoUrl != null && demoUrl!.isNotEmpty);
}

/// Resolves preview content for in-app document viewing (authenticated).
class DocumentPreviewService {
  DocumentPreviewService._();

  static String mimeFor(DocumentFileType type) => switch (type) {
    DocumentFileType.pdf => 'application/pdf',
    DocumentFileType.image => 'image/jpeg',
    DocumentFileType.doc =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    DocumentFileType.other => 'application/octet-stream',
  };

  static Future<DocumentPreviewContent> resolveContent({
    required String documentId,
    required DocumentFileType fileType,
    String? patientUserId,
  }) async {
    if (AppEnv.backendEnabled) {
      final role = AuthState.instance.user?.role;
      final useDoctorPath =
          patientUserId != null &&
          (role == UserRole.doctor ||
              role == UserRole.admin ||
              role == UserRole.mcareAssistant);

      final bytes = await DocumentsApi.instance.fetchBytes(
        documentId: documentId,
        patientUserId: useDoctorPath ? patientUserId : null,
      );
      return DocumentPreviewContent(bytes: bytes, mimeType: mimeFor(fileType));
    }

    final url = _demoUrl(documentId, fileType);
    return DocumentPreviewContent(demoUrl: url, mimeType: mimeFor(fileType));
  }

  /// Legacy URL resolver — prefer [resolveContent] for authenticated previews.
  static Future<String?> resolveUrl({
    required String documentId,
    required DocumentFileType fileType,
    String? patientUserId,
  }) async {
    if (AppEnv.backendEnabled) {
      final content = await resolveContent(
        documentId: documentId,
        fileType: fileType,
        patientUserId: patientUserId,
      );
      if (content.bytes != null) {
        return blob_url.createBlobUrl(content.bytes!, content.mimeType);
      }
      return content.demoUrl;
    }
    return _demoUrl(documentId, fileType);
  }

  static String? objectUrlFor(DocumentPreviewContent content) {
    if (content.bytes != null) {
      return blob_url.createBlobUrl(content.bytes!, content.mimeType);
    }
    return content.demoUrl;
  }

  static void revokeObjectUrl(String? url) {
    if (url != null && url.startsWith('blob:')) {
      blob_url.revokeBlobUrl(url);
    }
  }

  static String? _demoUrl(String id, DocumentFileType type) {
    final seed = Uri.encodeComponent(id);
    switch (type) {
      case DocumentFileType.image:
        return 'https://picsum.photos/seed/$seed/900/1200';
      case DocumentFileType.pdf:
      case DocumentFileType.doc:
      case DocumentFileType.other:
        return 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';
    }
  }

  static DocumentFileType inferFromCategoryLabel(String category) {
    final c = category.toLowerCase();
    if (c.contains('imaging') || c.contains('image') || c.contains('x-ray')) {
      return DocumentFileType.image;
    }
    return DocumentFileType.pdf;
  }
}

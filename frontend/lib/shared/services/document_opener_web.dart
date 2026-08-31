import 'dart:typed_data';

import '../../core/web/web_platform.dart' as web_platform;
import 'document_blob_url_web.dart';

/// Web document opening: wrap the bytes in a blob URL and let the browser do
/// what it is already good at — render the PDF, the image or the text inline
/// in a new tab, with its own print-to-PDF and save controls.
Future<bool> openDocumentBytes({
  required Uint8List bytes,
  required String mimeType,
  required String filename,
}) async {
  final url = createBlobUrl(bytes, mimeType);
  if (url.isEmpty) return false;

  web_platform.openWindow(url, '_blank');

  // The blob is deliberately not revoked here: the tab that just opened is
  // still fetching it, and revoking immediately leaves the reader with a blank
  // viewer. The browser reclaims it when the document is discarded.
  return true;
}

/// Opens an already-addressable URL — the fixture-mode path, where there are
/// no bytes to wrap.
Future<bool> openDocumentUrl(String url) async {
  web_platform.openWindow(url, '_blank');

  return true;
}

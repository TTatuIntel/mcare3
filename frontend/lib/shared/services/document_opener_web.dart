import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../core/web/web_platform.dart' as web_platform;
import 'document_blob_url_web.dart';

/// Web document opening: wrap the bytes in a blob URL and let the browser do
/// what it is already good at — render the PDF, the image or the report inline
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

/// Saves the bytes to the reader's device under [filename].
///
/// Genuinely different from opening on the web, and that difference is the
/// whole point: Download used to call [openDocumentBytes], so a patient at a
/// hospital reception who tapped Download got a new browser tab and no file.
/// A synthetic anchor carrying the `download` attribute is what actually puts
/// the document in their Downloads folder, under a name they can find again.
Future<bool> downloadDocumentBytes({
  required Uint8List bytes,
  required String mimeType,
  required String filename,
}) async {
  final url = createBlobUrl(bytes, mimeType);
  if (url.isEmpty) return false;

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename
    ..style.display = 'none';

  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();

  // Unlike the open path there is no tab still reading this one, but the save
  // is asynchronous — revoking in the same turn can truncate it on some
  // browsers, so the blob is released once the download has certainly started.
  Future<void>.delayed(const Duration(seconds: 30), () => revokeBlobUrl(url));

  return true;
}

/// Opens an already-addressable URL — the fixture-mode path, where there are
/// no bytes to wrap.
Future<bool> openDocumentUrl(String url) async {
  web_platform.openWindow(url, '_blank');

  return true;
}

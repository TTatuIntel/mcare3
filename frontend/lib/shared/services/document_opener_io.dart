import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Native document opening.
///
/// The web build hands the bytes to the browser as a blob URL and lets it
/// render the PDF in a tab. There is no equivalent on iOS or Android — the
/// blob-URL helper compiled to a stub that returned an empty string there, so
/// `openWindow('')` did nothing at all and every Open and Download on a phone
/// failed silently, with the spinner stopping and no file and no error.
///
/// The OS share sheet is the native answer: it carries "Open in…", Files,
/// Books, Drive and print, so a PDF the patient was sent is one tap from a
/// real viewer without this app shipping a PDF renderer of its own.
Future<bool> openDocumentBytes({
  required Uint8List bytes,
  required String mimeType,
  required String filename,
}) async {
  // cross_file ignores XFile's `name` everywhere except web, so the readable
  // filename has to travel as an explicit override or the recipient app gets
  // a temp name with no extension and cannot tell what it was handed.
  await Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
    fileNameOverrides: [filename],
  );

  return true;
}

/// Opens an already-addressable URL — the fixture-mode path, where there are
/// no bytes to hand the share sheet.
Future<bool> openDocumentUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;

  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

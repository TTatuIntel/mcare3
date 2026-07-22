import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Save binary data to a user-chosen location (desktop/web/mobile).
Future<bool> saveBytesAsFile({
  required Uint8List bytes,
  required String suggestedName,
  List<String> allowedExtensions = const ['csv'],
}) async {
  final path = await FilePicker.platform.saveFile(
    fileName: suggestedName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );
  return path != null;
}

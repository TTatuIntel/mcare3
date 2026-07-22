import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Builds [http.MultipartFile] from a [PlatformFile] on web and IO.
class MultipartFileBuilder {
  MultipartFileBuilder._();

  static Future<http.MultipartFile> fromPlatformFile(
    PlatformFile file, {
    String fieldName = 'file',
  }) async {
    final bytes = file.bytes;
    if (bytes != null) {
      return http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: file.name,
      );
    }
    if (!kIsWeb && file.path != null) {
      return http.MultipartFile.fromPath(
        fieldName,
        file.path!,
        filename: file.name,
      );
    }
    throw StateError('Could not read file bytes for upload.');
  }

  static Future<http.MultipartFile> fromBytes(
    Uint8List bytes, {
    required String filename,
    String fieldName = 'file',
  }) =>
      Future.value(http.MultipartFile.fromBytes(
        fieldName,
        bytes,
        filename: filename,
      ));
}

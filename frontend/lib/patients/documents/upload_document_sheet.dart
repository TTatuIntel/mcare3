import '../../shared/models/document.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/widgets/document_upload_form.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'package:flutter/material.dart';

/// The patient adding a document to their own record.
///
/// The form is shared with the staff-side sheet — see [DocumentUploadForm].
/// The two were separate files carrying two copies of the same picker, the
/// same validation and the same file chooser, differing only in where they
/// posted and which category they defaulted to.
class UploadDocumentSheet {
  UploadDocumentSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'Upload document',
      subtitle: 'Add lab results, prescriptions, imaging and more.',
      child: DocumentUploadForm(
        initialCategory: DocumentCategory.labResult,
        onSubmit:
            ({
              required file,
              required title,
              required category,
              required fileType,
              required sizeBytes,
              description,
            }) => DocumentsState.instance.uploadDocument(
              file: file,
              title: title,
              category: category,
              fileType: fileType,
              sizeBytes: sizeBytes,
              description: description,
            ),
      ),
    );
  }
}

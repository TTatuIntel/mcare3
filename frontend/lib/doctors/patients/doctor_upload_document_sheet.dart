import 'package:flutter/material.dart';

import '../../shared/staff/staff_upload_document_sheet.dart';

/// Moved to shared/staff so admin surfaces can use it too.
///
/// Kept as an alias rather than renamed at every call site — the sheet is the
/// same one, and breaking working screens to rename a class is not a trade
/// worth making.
class DoctorUploadDocumentSheet {
  DoctorUploadDocumentSheet._();

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
  }) => StaffUploadDocumentSheet.show(
    context,
    patientId: patientId,
    patientName: patientName,
  );
}

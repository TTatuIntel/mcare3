import 'package:flutter/material.dart';

import '../../core/api/documents_api.dart';
import '../../core/env/app_env.dart';
import '../models/document.dart';
import '../services/doctor_patient_detail_service.dart';
import '../state/staff_models.dart';
import '../state/staff_state.dart';
import '../widgets/document_upload_form.dart';
import '../widgets/glass_sheet.dart';

/// Files a document into a patient's record on their behalf.
///
/// Shared by doctors and admin staff: DocumentsApi picks the route from the
/// signed-in role, because admin staff are not on a caseload and the doctor
/// endpoints reject them outright. Lives in shared/ rather than doctors/ so the
/// admin surfaces can reach it without importing across role layers.
///
/// The form itself is [DocumentUploadForm], shared with the patient's own
/// upload sheet — what differs between filing your own document and filing one
/// for someone else is the destination and the default category, and that is
/// all that differs here.
class StaffUploadDocumentSheet {
  StaffUploadDocumentSheet._();

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
  }) {
    return GlassSheet.show(
      context,
      title: 'Upload document',
      subtitle: 'For $patientName',
      child: DocumentUploadForm(
        initialCategory: DocumentCategory.consultationNote,
        successMessage: 'Document uploaded for $patientName.',
        onSubmit:
            ({
              required file,
              required title,
              required category,
              required fileType,
              required sizeBytes,
              description,
            }) async {
              if (!AppEnv.backendEnabled) {
                StaffState.instance.addDocumentForPatient(
                  StaffPatientDocument(
                    id: 'sdoc_${DateTime.now().millisecondsSinceEpoch}',
                    patientId: patientId,
                    title: title,
                    category: category.label,
                    fileType: fileType,
                    uploadedAt: DateTime.now(),
                    uploadedBy: 'Doctor',
                    // Mock parity with the server: anything staff file is
                    // clinical, so it carries the same no-delete protection
                    // offline as online.
                    source: DocumentSource.clinician,
                  ),
                );
                return;
              }

              await DocumentsApi.instance.create(
                patientUserId: patientId,
                file: file,
                title: title,
                category: category,
                fileType: fileType,
                description: description,
              );
              // Only the documents changed, so only the documents are
              // re-pulled — not the whole chart.
              await DoctorPatientDetailService.instance.loadDocuments(
                patientId,
              );
            },
      ),
    );
  }
}

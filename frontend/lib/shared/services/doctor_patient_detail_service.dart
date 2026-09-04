import '../../core/api/doctor_api.dart';
import '../../core/api/documents_api.dart';
import '../../core/env/app_env.dart';
import '../models/document.dart';
import '../state/staff_models.dart';
import '../state/staff_state.dart';

/// Loads per-patient workspace detail from the API into `StaffState`.
class DoctorPatientDetailService {
  DoctorPatientDetailService._();
  static final DoctorPatientDetailService instance =
      DoctorPatientDetailService._();

  Future<bool> loadPatient(String patientId) async {
    if (!AppEnv.backendEnabled) return true;
    final data = await DoctorApi.instance.patientDetail(patientId);
    if (data == null) return false;
    StaffState.instance.mergePatientDetail(patientId, data);
    return true;
  }

  /// Re-pulls just this patient's documents.
  ///
  /// Filing one document used to reload the entire chart — the vitals, the
  /// medications, the appointments, the alert history — to show a single new
  /// row. That is a lot of bytes and a visible stall for a clinician who
  /// changed one thing, and it is the reason the list was refreshed only at
  /// moments the code remembered to.
  Future<bool> loadDocuments(String patientId) async {
    if (!AppEnv.backendEnabled) return true;
    try {
      final documents = await DocumentsApi.instance.listForPatient(patientId);
      StaffState.instance.replaceDocumentsForPatient(
        patientId,
        documents
            .map(
              (d) => StaffPatientDocument(
                id: d.id,
                patientId: patientId,
                title: d.title,
                category: d.category.label,
                uploadedAt: d.uploadedAt,
                uploadedBy: d.uploadedBy,
                fileType: d.fileType,
                mimeType: d.mimeType,
                downloadName: d.downloadName,
                description: d.description,
                hasFile: d.hasFile,
                source: d.source,
                removalRequested: d.removalRequested,
                removalReason: d.removalReason,
              ),
            )
            .toList(growable: false),
      );
      return true;
    } catch (_) {
      // The list already on screen is more useful than an error over it.
      return false;
    }
  }
}

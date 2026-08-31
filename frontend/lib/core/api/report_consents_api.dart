import 'dart:typed_data';

import '../env/app_env.dart';
import 'api_client.dart';

/// Patient-facing report API.
///
/// The historical class name is retained so existing imports do not break.
/// Patient consent/permission is NOT part of report creation or issue.
///
/// Workflow ownership:
/// - Admin creates the report.
/// - Doctor reviews/signs.
/// - Admin approves and shares it.
/// - Patient can view/download their issued report.
/// - Only the patient can delete their own issued document.
///
/// The backend must enforce ownership/authorization for deletion. A client-side
/// check is not a security boundary.
class ReportConsentsApi {
  ReportConsentsApi._();

  static final ReportConsentsApi instance = ReportConsentsApi._();

  /// Reports visible to the signed-in patient.
  ///
  /// The existing backend route is kept for compatibility even though reports
  /// are no longer consent requests.
  Future<List<Map<String, dynamic>>> list() async {
    if (!AppEnv.backendEnabled) return const [];

    final res = await ApiClient.instance.get('/patient/report-consents');
    final list = res['data']?['report_requests'] as List? ?? const [];

    return list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  /// The patient's issued report as authenticated printable bytes.
  Future<Uint8List> documentBytes(String id) {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled.');
    }

    final safeId = id.trim();
    if (safeId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Report id cannot be empty.');
    }

    return ApiClient.instance.getBytes(
      '/patient/report-consents/$safeId/document',
    );
  }

  /// Delete the signed-in patient's own issued report/document.
  ///
  /// This MUST be ownership-checked on the backend. An admin/doctor must not be
  /// able to use this patient route to delete a patient's uploaded report.
  Future<void> deleteOwnDocument(String id) async {
    if (!AppEnv.backendEnabled) return;

    final safeId = id.trim();
    if (safeId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Report id cannot be empty.');
    }

    await ApiClient.instance.delete(
      '/patient/report-consents/$safeId',
    );
  }

  /// Backwards-friendly short alias for patient-owned deletion.
  Future<void> delete(String id) => deleteOwnDocument(id);
}

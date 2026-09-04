import '../../shared/models/document.dart';
import '../../shared/models/document_request.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

/// The patient's side of asking the care team for a document.
class DocumentRequestsApi {
  DocumentRequestsApi._();
  static final DocumentRequestsApi instance = DocumentRequestsApi._();

  Future<List<DocumentRequest>> listMine() async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get('/patient/document-requests');
    final rows = res['data']?['requests'] as List? ?? const [];
    return rows
        .map(
          (e) => PatientDomainMapper.documentRequestFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  Future<DocumentRequest?> submit({
    required String title,
    required DocumentCategory category,
    required DocumentRequestTarget target,
    String? note,
    String? targetDoctorId,
    DateTime? neededBy,
    DateTime? periodFrom,
    DateTime? periodTo,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/document-requests',
      body: PatientDomainMapper.documentRequestToApi(
        title: title,
        category: category,
        target: target,
        note: note,
        targetDoctorId: targetDoctorId,
        neededBy: neededBy,
        periodFrom: periodFrom,
        periodTo: periodTo,
      ),
    );
    final json = res['data']?['request'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentRequestFromApi(json);
  }

  Future<DocumentRequest?> cancel(String requestId) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.delete(
      '/patient/document-requests/$requestId',
    );
    final json = res['data']?['request'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.documentRequestFromApi(json);
  }
}

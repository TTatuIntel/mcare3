import '../../shared/models/vital.dart';
import '../../shared/models/vital_report_request.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class VitalReportsApi {
  VitalReportsApi._();
  static final VitalReportsApi instance = VitalReportsApi._();

  Future<VitalReportRequest?> submit({
    required DateTime from,
    required DateTime to,
    required List<VitalKey> vitals,
    String? note,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/vital-report-requests',
      body: PatientDomainMapper.vitalReportRequestToApi(
        from: from,
        to: to,
        vitals: vitals,
        note: note,
      ),
    );
    final json = res['data']?['request'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.vitalReportRequestFromApi(json);
  }

  Future<VitalReportRequest?> cancel(String requestId) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/vital-report-requests/$requestId',
    );
    final json = res['data']?['request'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.vitalReportRequestFromApi(json);
  }
}

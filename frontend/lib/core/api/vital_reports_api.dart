import '../../shared/models/vital.dart';
import '../../shared/models/vital_report_request.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class VitalReportsApi {
  VitalReportsApi._();
  static final VitalReportsApi instance = VitalReportsApi._();

  /// The patient's own requests, with the trail of who has touched each one.
  ///
  /// The session carries these too, but a patient watching a request they just
  /// raised needs to see it move without a full sync — "someone has picked
  /// this up" is the whole point of a shared queue.
  Future<List<VitalReportRequest>> listMine() async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get('/patient/vital-report-requests');
    final rows = res['data']?['requests'] as List? ?? const [];
    return rows
        .map(
          (e) => PatientDomainMapper.vitalReportRequestFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

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

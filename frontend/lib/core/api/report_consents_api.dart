import '../env/app_env.dart';
import 'api_client.dart';

/// Patient-facing consent surface for customised reports drawn from their
/// record. The patient sees exactly which sections staff want to disclose,
/// to whom, and why — then approves or declines.
class ReportConsentsApi {
  ReportConsentsApi._();
  static final ReportConsentsApi instance = ReportConsentsApi._();

  Future<List<Map<String, dynamic>>> list() async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get('/patient/report-consents');
    final list = res['data']?['report_requests'] as List? ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>?> approve(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/report-consents/$id/approve',
    );
    return (res['data']?['report_request'] as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> decline(String id, {String? reason}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/report-consents/$id/decline',
      body: reason == null || reason.isEmpty ? null : {'reason': reason},
    );
    return (res['data']?['report_request'] as Map?)?.cast<String, dynamic>();
  }
}

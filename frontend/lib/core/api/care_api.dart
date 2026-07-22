import '../../shared/models/care_provider.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class CareApi {
  CareApi._();
  static final CareApi instance = CareApi._();

  Future<List<CareProvider>> listProviders() async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get('/patient/care/providers');
    final list = res['data']?['providers'] as List? ?? [];
    return list
        .map((e) =>
            PatientDomainMapper.careProviderFromApi(e as Map<String, dynamic>))
        .toList();
  }

  Future<CareRequest?> requestProvider({
    required String providerId,
    String? reason,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/care/requests',
      body: {
        'provider_id': providerId,
        if (reason != null) 'reason': reason,
      },
    );
    final json = res['data']?['request'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.careRequestFromApi(json);
  }

  Future<CareRequest?> cancelRequest(String requestId) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/care/requests/$requestId',
    );
    final json = res['data']?['request'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.careRequestFromApi(json);
  }
}

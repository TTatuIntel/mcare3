import '../../shared/models/vital.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class VitalsApi {
  VitalsApi._();
  static final VitalsApi instance = VitalsApi._();

  Future<List<VitalReading>> history({
    VitalKey? vital,
    int? days,
  }) async {
    if (!AppEnv.backendEnabled) return const [];
    final query = <String, String>{};
    if (vital != null) query['vital_key'] = vital.name;
    if (days != null) query['days'] = '$days';
    final uri = query.isEmpty
        ? '/patient/vitals'
        : '/patient/vitals?${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final res = await ApiClient.instance.get(uri);
    final list = res['data']?['vitals'] as List? ?? [];
    return list
        .map((e) => PatientDomainMapper.vitalFromApi(e as Map<String, dynamic>))
        .toList();
  }

  Future<VitalReading?> record({
    required VitalKey vital,
    required double value,
    double? secondaryValue,
    DateTime? recordedAt,
    String? note,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/vitals',
      body: PatientDomainMapper.vitalToApi(
        vital: vital,
        value: value,
        secondaryValue: secondaryValue,
        recordedAt: recordedAt,
        note: note,
      ),
    );
    final json = res['data']?['vital'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.vitalFromApi(json);
  }

  Future<List<VitalKey>?> updateTracked(List<VitalKey> vitals) async {
    if (!AppEnv.backendEnabled) return vitals;
    final res = await ApiClient.instance.patch(
      '/patient/tracked-vitals',
      body: {
        'tracked_vitals': vitals.map((v) => v.name).toList(),
      },
    );
    final list = res['data']?['tracked_vitals'] as List? ?? [];
    return list
        .map((e) => VitalKey.values.firstWhere((v) => v.name == e))
        .toList();
  }
}

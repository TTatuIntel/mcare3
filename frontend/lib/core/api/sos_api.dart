import '../../shared/models/sos.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class SosApi {
  SosApi._();
  static final SosApi instance = SosApi._();

  Future<SosEvent?> trigger({
    required EmergencyKind kind,
    String? locationLabel,
    double? latitude,
    double? longitude,
    String? note,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/sos',
      body: PatientDomainMapper.sosTriggerToApi(
        kind: kind,
        locationLabel: locationLabel,
        latitude: latitude,
        longitude: longitude,
        note: note,
      ),
    );
    final json = res['data']?['event'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.sosEventFromApi(json);
  }

  Future<SosEvent?> resolve(
    String eventId, {
    required SosStatus status,
    String? respondedBy,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/sos/$eventId',
      body: {
        'status': status.name,
        if (respondedBy != null) 'responded_by': respondedBy,
      },
    );
    final json = res['data']?['event'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.sosEventFromApi(json);
  }
}

import '../../shared/models/medication.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class MedicationsApi {
  MedicationsApi._();
  static final MedicationsApi instance = MedicationsApi._();

  Future<Medication?> create(Medication med) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/medications',
      body: PatientDomainMapper.medicationToApi(med),
    );
    final json = res['data']?['medication'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.medicationFromApi(json);
  }

  Future<Medication?> update(
    String id, {
    String? name,
    String? dosage,
    String? frequency,
    String? instructions,
    int? refillsLeft,
    DateTime? expiryDate,
    bool? active,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (dosage != null) body['dosage'] = dosage;
    if (frequency != null) body['frequency'] = frequency;
    if (instructions != null) body['instructions'] = instructions;
    if (refillsLeft != null) body['refills_left'] = refillsLeft;
    if (expiryDate != null) body['expiry_date'] = expiryDate.toIso8601String();
    if (active != null) body['active'] = active;
    final res = await ApiClient.instance.patch(
      '/patient/medications/$id',
      body: body,
    );
    final json = res['data']?['medication'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.medicationFromApi(json);
  }

  Future<bool> archive(String id) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete('/patient/medications/$id');
    return true;
  }

  Future<MedicationDose?> recordDose(
    String doseId,
    DoseStatus status, {
    Map<String, Medication>? medsById,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/medication-doses/$doseId',
      body: PatientDomainMapper.doseStatusToApi(status),
    );
    final json = res['data']?['dose'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.doseFromApi(
      json,
      medsById: medsById ?? const {},
    );
  }
}

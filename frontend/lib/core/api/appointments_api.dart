import '../../shared/models/appointment.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

class AppointmentsApi {
  AppointmentsApi._();
  static final AppointmentsApi instance = AppointmentsApi._();

  Future<Appointment?> create(Appointment appt) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/appointments',
      body: PatientDomainMapper.appointmentToApi(appt),
    );
    final json = res['data']?['appointment'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.appointmentFromApi(json);
  }

  Future<Appointment?> update(
    String id, {
    AppointmentStatus? status,
    DateTime? scheduledAt,
    String? cancellationReason,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status.name;
    if (scheduledAt != null) {
      body['scheduled_at'] = scheduledAt.toIso8601String();
    }
    if (cancellationReason != null) {
      body['cancellation_reason'] = cancellationReason;
    }
    final res = await ApiClient.instance.patch(
      '/patient/appointments/$id',
      body: body,
    );
    final json = res['data']?['appointment'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.appointmentFromApi(json);
  }

  Future<bool> cancel(String id) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete('/patient/appointments/$id');
    return true;
  }
}

import '../../shared/auth/auth_state.dart';
import '../../shared/models/user_role.dart';
import '../../shared/state/staff_models.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'staff_mapper.dart';

/// Emergencies including the ones already closed.
///
/// The live queue that [StaffState] holds is deliberately only what is still
/// open — that is what the banners, the badge and the dashboard count from.
/// But an emergency that has been handed to a provider, or closed an hour
/// ago, is exactly the one a coordinator needs to follow up on, and it was
/// gone from the app the moment it stopped being active.
///
/// So this reads the same events with their outcome and their response trail
/// attached, and hands them straight to the screen that asked. Nothing here
/// is written into the shared queue: a closed emergency must never re-enter
/// the list of things demanding attention.
class SosFollowUpApi {
  SosFollowUpApi._();
  static final SosFollowUpApi instance = SosFollowUpApi._();

  /// Every emergency in scope, live and closed, newest first.
  Future<List<StaffPatientSos>> fetchAll() async {
    if (!AppEnv.backendEnabled) return const [];
    final doctor = AuthState.instance.user?.role == UserRole.doctor;
    final path = doctor
        ? '/doctor/sos?status=all'
        : '/admin/sos-events?status=all';

    final res = await ApiClient.instance.get(path);
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    final rows = (data?['sos_events'] as List?) ?? const [];

    return rows.whereType<Map>().map((e) {
      final json = e.cast<String, dynamic>();
      return StaffMapper.sosFromApi(
        json,
        patientId: (json['patient_id'] ?? '').toString(),
      );
    }).toList();
  }
}

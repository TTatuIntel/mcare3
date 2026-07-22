import '../../core/api/admin_api.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../state/staff_state.dart';

/// Syncs platform-wide SOS events for admin / assistant roles.
class AdminSosService {
  AdminSosService._();
  static final AdminSosService instance = AdminSosService._();

  Future<bool> syncFromApi() async {
    if (!AppEnv.backendEnabled) return true;

    try {
      final rows = await AdminApi.instance.listSosEvents();
      final events = rows
          .map((e) => StaffMapper.sosFromApi(
                e,
                patientId: (e['patient_id'] ?? '').toString(),
              ))
          .toList();
      StaffState.instance.mergeSosEvents(events);
      return true;
    } catch (_) {
      return false;
    }
  }
}

import '../../shared/models/user_role.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/services/admin_session_service.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/doctor_session_service.dart';
import '../../shared/services/patient_session_service.dart';
import '../async/app_busy.dart';
import '../env/app_env.dart';

/// Standardized, non-blocking session refresh used by [SessionPoller].
abstract final class BackgroundSessionSync {
  BackgroundSessionSync._();

  static bool _inFlight = false;

  /// Returns true when fresh data was applied.
  static Future<bool> refresh({
    required UserRole role,
    bool urgent = false,
  }) async {
    if (!AppEnv.backendEnabled) return false;
    if (_inFlight) return false;

    _inFlight = true;
    // Marks the refresh so screens can tell "nothing outstanding" apart from
    // "not loaded yet" and hold their last known picture instead of blanking.
    StaffState.instance.beginSync();
    try {
      // Zone-marked as unattended: nothing this sweep does may raise the
      // on-screen indicator or the top bar. The user did not ask for it.
      return await AppBusy.runBackground(() async {
        switch (role) {
          case UserRole.patient:
            return PatientSessionService.instance.syncFromApi(background: true);
          case UserRole.doctor:
            return DoctorSessionService.instance.syncFromApi(background: true);
          case UserRole.mcareAssistant:
            // Keep delegated permissions live: an admin can grant/revoke at any
            // time and the change must reach the assistant without re-login.
            await AuthService.instance.refreshAssistantPermissions();
            return AdminSessionService.instance.syncFromApi(background: true);
          case UserRole.admin:
            return AdminSessionService.instance.syncFromApi(background: true);
          default:
            return false;
        }
      });
    } catch (_) {
      // Background reconciliation must never crash a timer, popup lifecycle,
      // or the visible page. Stores retain their last successful snapshot and
      // the next Reverb event/poll/resume will retry.
      return false;
    } finally {
      StaffState.instance.endSync();
      _inFlight = false;
    }
  }
}

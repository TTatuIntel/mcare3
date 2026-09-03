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

  static Future<bool>? _activeRefresh;
  static bool _refreshRequested = false;
  static UserRole? _requestedRole;
  static bool _requestedUrgent = false;

  /// Returns true when fresh data was applied.
  static Future<bool> refresh({required UserRole role, bool urgent = false}) {
    if (!AppEnv.backendEnabled) return Future<bool>.value(false);

    // Socket, pulse, push and the safety sweep can all notice the same burst.
    // Never discard a refresh merely because another one is in flight. Every
    // caller joins the active drain, and a request that arrives during the
    // network round trip schedules one final reconciliation pass afterwards.
    _requestedRole = role;
    _requestedUrgent = _requestedUrgent || urgent;
    _refreshRequested = true;
    return _activeRefresh ??= _drain();
  }

  static Future<bool> _drain() async {
    var refreshed = false;
    // Marks the refresh so screens can tell "nothing outstanding" apart from
    // "not loaded yet" and hold their last known picture instead of blanking.
    StaffState.instance.beginSync();
    try {
      do {
        _refreshRequested = false;
        final role = _requestedRole;
        // Kept for the queue contract: an urgent request is never lost behind
        // an ordinary one, even though every role currently uses the same
        // canonical session endpoint.
        _requestedUrgent = false;
        if (role == null) break;

        try {
          // Zone-marked as unattended: nothing this sweep does may raise the
          // on-screen indicator or the top bar. The user did not ask for it.
          final ok = await AppBusy.runBackground(() async {
            switch (role) {
              case UserRole.patient:
                return PatientSessionService.instance.syncFromApi(
                  background: true,
                );
              case UserRole.doctor:
                return DoctorSessionService.instance.syncFromApi(
                  background: true,
                );
              case UserRole.mcareAssistant:
                // Keep delegated permissions live: an admin can grant/revoke
                // at any time and the change must arrive without re-login.
                await AuthService.instance.refreshAssistantPermissions();
                return AdminSessionService.instance.syncFromApi(
                  background: true,
                );
              case UserRole.admin:
                return AdminSessionService.instance.syncFromApi(
                  background: true,
                );
              default:
                return false;
            }
          });
          refreshed = refreshed || ok;
        } catch (_) {
          // Retain the last successful snapshot. A request that landed while
          // this one failed is still drained by the loop below.
        }
      } while (_refreshRequested);

      return refreshed;
    } finally {
      StaffState.instance.endSync();
      _activeRefresh = null;
    }
  }
}

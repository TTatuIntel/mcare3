import 'dart:async';

import '../../shared/models/user_role.dart';
import '../../shared/services/admin_session_service.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/doctor_session_service.dart';
import '../../shared/services/patient_session_service.dart';
import '../../shared/state/notification_state.dart';
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
    try {
      switch (role) {
        case UserRole.patient:
          return PatientSessionService.instance.syncFromApi(background: true);
        case UserRole.doctor:
          final applied =
              await DoctorSessionService.instance.syncFromApi(background: true);
          unawaited(NotificationState.instance.loadStaffNotificationStates());
          return applied;
        case UserRole.mcareAssistant:
          // Keep delegated permissions live: an admin can grant/revoke at any
          // time and the change must reach the assistant without re-login.
          await AuthService.instance.refreshAssistantPermissions();
          final applied =
              await AdminSessionService.instance.syncFromApi(background: true);
          unawaited(NotificationState.instance.loadStaffNotificationStates());
          return applied;
        case UserRole.admin:
          final applied =
              await AdminSessionService.instance.syncFromApi(background: true);
          unawaited(NotificationState.instance.loadStaffNotificationStates());
          return applied;
        default:
          return false;
      }
    } finally {
      _inFlight = false;
    }
  }
}

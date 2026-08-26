import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/user_role.dart';
import '../state/staff_state.dart';

import '../../core/api/api_client.dart';
import '../../core/env/app_env.dart';
import '../../core/mock/mock_bootstrap.dart';
import '../../core/mock/mock_otp_service.dart';
import '../services/auth_storage.dart';
import '../../core/push/push_notification_service.dart';
import '../services/sos_ring_service.dart';
import '../alerts/alert_center.dart';
import '../widgets/sos_alert_popup.dart';

/// Canonical mCare Assistant permission keys (§9.4 of documentation).
class AssistantPermissions {
  AssistantPermissions._();

  static const canApproveHealthworkers = 'can_approve_healthworkers';
  static const canManageCareRequests = 'can_manage_care_requests';
  static const canAssignPatients = 'can_assign_patients';
  static const canCreateUsers = 'can_create_users';
  static const canChangeUserTypes = 'can_change_user_types';
  static const canRegisterAdmin = 'can_register_admin';
  static const canRegisterAssistant = 'can_register_assistant';
  static const canViewActivityLogs = 'can_view_activity_logs';
  static const canViewSecurityIncidents = 'can_view_security_incidents';
  static const canAccessEmergencyLocation = 'can_access_emergency_location';
  static const canManageAdvertising = 'can_manage_advertising';

  /// Grants access to create, edit, and disable global vital catalog entries.
  /// Doctors always have this right; admins have it unconditionally.
  static const canManageVitalCatalog = 'can_manage_vital_catalog';

  static const all = <String>[
    canApproveHealthworkers,
    canManageCareRequests,
    canAssignPatients,
    canCreateUsers,
    canChangeUserTypes,
    canRegisterAdmin,
    canRegisterAssistant,
    canViewActivityLogs,
    canViewSecurityIncidents,
    canAccessEmergencyLocation,
    canManageAdvertising,
    canManageVitalCatalog,
  ];
}

/// Single auth notifier. UI listens with ValueListenableBuilder.
class AuthState extends ChangeNotifier {
  AuthState._();
  static final AuthState instance = AuthState._();

  AppUser? _user;

  /// Demo password for mock auth (patient login uses `demo-password`).
  String _password = 'demo-password';

  /// Assistant permission grants. Admin grants the whole list; assistants
  /// see only what they were granted.
  final Set<String> _assistantPermissions = <String>{};

  /// Cleanup hooks run on [logout] so role modules can reset transient UI
  /// state (e.g. dashboard popups) without shared code importing role widgets.
  /// Register once at startup via [addLogoutCleanup].
  static final List<VoidCallback> _logoutCleanups = <VoidCallback>[];

  static void addLogoutCleanup(VoidCallback cleanup) {
    if (!_logoutCleanups.contains(cleanup)) _logoutCleanups.add(cleanup);
  }

  AppUser? get user => _user;
  bool get isAuthenticated => _user != null;
  UserRole get role => _user?.role ?? UserRole.guest;

  /// Admins are unrestricted — any check returns true. Assistants are
  /// checked against the granted-permissions set. Other roles always false.
  bool hasAssistantPermission(String key) {
    final r = _user?.role;
    if (r == UserRole.admin) return true;
    if (r == UserRole.mcareAssistant) {
      return _assistantPermissions.contains(key);
    }
    return false;
  }

  void setAssistantPermissions(Iterable<String> keys) {
    _assistantPermissions
      ..clear()
      ..addAll(keys);
    notifyListeners();
  }

  void signIn(
    AppUser user, {
    String? password,
    Iterable<String>? assistantPermissions,
  }) {
    _user = user;
    if (password != null) _password = password;
    _assistantPermissions
      ..clear()
      ..addAll(assistantPermissions ?? const <String>[]);
    notifyListeners();
  }

  void updateUser(AppUser user) {
    _user = user;
    notifyListeners();
  }

  /// Applies a full user payload returned by the backend (profile edit, avatar,
  /// email change, …), refreshing in-memory state and the persisted session so
  /// the change survives a reload. If the API returned a new token, it is set.
  Future<void> applyServerUser(
    Map<String, dynamic> userMap, {
    String? token,
  }) async {
    _user = AppUser.fromJson(userMap);
    if (token != null) ApiClient.instance.setToken(token);
    notifyListeners();
    final activeToken = token ?? ApiClient.instance.token;
    if (activeToken == null) return;
    final stored = await AuthStorage.read();
    await AuthStorage.save(
      token: activeToken,
      user: userMap,
      hasHealthProfile: stored?.hasHealthProfile ?? false,
    );
  }

  /// Verifies current password, OTP, then applies new password (mock).
  Future<PasswordChangeResult> changePassword({
    required String currentPassword,
    required String newPassword,
    required String otpCode,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    if (currentPassword != _password) {
      return PasswordChangeResult.wrongPassword;
    }
    if (newPassword.length < 8) {
      return PasswordChangeResult.weakPassword;
    }
    if (!MockOtpService.verify(otpCode)) {
      return PasswordChangeResult.invalidOtp;
    }
    _password = newPassword;
    MockOtpService.clear();
    notifyListeners();
    return PasswordChangeResult.success;
  }

  void signOut() {
    // Revoke server-side session (best-effort; don't block UI on failure).
    if (AppEnv.backendEnabled && ApiClient.instance.token != null) {
      ApiClient.instance
          .post('/auth/logout')
          .catchError((_) => <String, dynamic>{});
    }
    PushNotificationService.instance.unregisterOnLogout();
    ApiClient.instance.setToken(null);
    AuthStorage.clear();
    _user = null;
    _assistantPermissions.clear();
    StaffState.instance.clear();
    for (final cleanup in _logoutCleanups) {
      cleanup();
    }
    SosAlertPopup.reset();
    // Drop escalation history too, or the next user inherits this one's
    // snoozes and "already shown" state.
    AlertCenter.instance.reset();
    SosRingService.instance.stop();
    MockBootstrap.clearPatientSession();
    notifyListeners();
  }
}

enum PasswordChangeResult { success, wrongPassword, weakPassword, invalidOtp }

import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/sos_state.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/alerts/alert_center.dart';
import '../env/app_env.dart';
import 'background_session_sync.dart';
import 'realtime_channel.dart';

/// Standard background refresh for all signed-in roles.
///
/// - Runs on a fixed interval (30s normal, 8s when SOS/alerts are active)
/// - Skips overlapping requests
/// - Only rebuilds UI when session data actually changed
/// - Surfaces toasts only for new critical alerts / SOS events
///
/// When all Reverb subscriptions are confirmed this automatically drops to
/// [fallbackInterval] and becomes a reconciliation sweep for missed events.
/// A disconnect immediately restores normal/urgent polling.
class SessionPoller {
  SessionPoller._();
  static final SessionPoller instance = SessionPoller._();

  static const Duration normalInterval = Duration(seconds: 30);
  static const Duration urgentInterval = Duration(seconds: 8);
  static const Duration initialDelay = Duration(seconds: 3);

  /// Post-Reverb reconciliation sweep interval (§7.1).
  static const Duration fallbackInterval = Duration(minutes: 5);

  Timer? _timer;
  Timer? _initialTimer;
  BuildContext? _context;
  int _openAlerts = 0;
  int _activeSos = 0;

  void attach(BuildContext context) {
    if (!AppEnv.backendEnabled) return;
    final role = AuthState.instance.user?.role;
    if (role == null) return;
    if (role != UserRole.patient &&
        role != UserRole.doctor &&
        role != UserRole.admin &&
        role != UserRole.mcareAssistant) {
      return;
    }
    _context = context;
    _snapshotCounts();
    _scheduleNext();
    _initialTimer?.cancel();
    _initialTimer = Timer(initialDelay, _tick);
  }

  void detach() {
    _timer?.cancel();
    _timer = null;
    _initialTimer?.cancel();
    _initialTimer = null;
    _context = null;
  }

  /// Out-of-band background sync (does not reset the interval timer).
  void triggerNow() {
    if (!AppEnv.backendEnabled) return;
    Future.microtask(_tick);
  }

  /// Called by [RealtimeChannel] after subscription or disconnect.
  void onRealtimeStatusChanged({bool refresh = false}) {
    if (_context == null) return;
    _scheduleNext();
    if (refresh) triggerNow();
  }

  void _scheduleNext() {
    _timer?.cancel();
    final user = AuthState.instance.user;
    final interval = RealtimeChannel.instance.isSubscribed
        ? fallbackInterval
        : user?.role == UserRole.patient
        ? (SosState.instance.hasActiveSos ? urgentInterval : normalInterval)
        : (_activeSos > 0 || _openAlerts > 0 ? urgentInterval : normalInterval);
    _timer = Timer(interval, () async {
      await _tick();
      _scheduleNext();
    });
  }

  void _snapshotCounts() {
    final scope = _scopePatientIds();
    _openAlerts = StaffState.instance.alerts
        .where(
          (a) => !a.acknowledged && !a.resolved && scope.contains(a.patientId),
        )
        .length;
    _activeSos = StaffState.instance.patientSos
        .where((e) => scope.contains(e.patientId) && e.isActive)
        .length;
  }

  Set<String> _scopePatientIds() {
    final user = AuthState.instance.user;
    if (user == null) return {};
    if (user.role == UserRole.doctor) {
      return StaffState.instance
          .assignedPatientsForDoctor()
          .map((p) => p.id)
          .toSet();
    }
    if (user.role == UserRole.admin || user.role == UserRole.mcareAssistant) {
      return {
        ...StaffState.instance.patients.map((p) => p.id),
        ...StaffState.instance.patientSos.map((e) => e.patientId),
      };
    }
    return {};
  }

  Future<void> _tick() async {
    final user = AuthState.instance.user;
    if (user == null) return;

    final beforeAlerts = _openAlerts;
    final beforeSos = _activeSos;

    final ok = await BackgroundSessionSync.refresh(role: user.role);
    if (!ok) return;

    if (user.role == UserRole.patient) {
      _maybeNotifyPatientUrgent(beforeSos);
      return;
    }

    final scope = _scopePatientIds();
    final alertList = StaffState.instance.alerts
        .where((a) => !a.acknowledged && scope.contains(a.patientId))
        .toList();
    final sosList = StaffState.instance.patientSos
        .where((e) => scope.contains(e.patientId) && e.isActive)
        .toList();

    _openAlerts = alertList.length;
    _activeSos = sosList.length;

    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;

    if (_openAlerts > beforeAlerts) {
      final critical = alertList
          .where((a) => a.severity == RiskLevel.critical)
          .length;
      AppToast.show(
        ctx,
        message: critical > 0
            ? '$critical new critical alert${critical == 1 ? '' : 's'}'
            : 'New patient alert',
        kind: AppToastKind.warning,
      );
    }

    if (_activeSos > beforeSos) {
      AppToast.show(
        ctx,
        message: 'New SOS — respond immediately',
        kind: AppToastKind.error,
      );
      final role = user.role;
      if (role == UserRole.doctor ||
          role == UserRole.admin ||
          role == UserRole.mcareAssistant) {
        // Hand it to the engine; the banner layer decides what appears.
        // Pushing a popup from here is what used to cover the page.
        AlertCenter.instance.refresh();
      }
    }
  }

  void _maybeNotifyPatientUrgent(int beforeSos) {
    if (!SosState.instance.hasActiveSos) return;
    final ctx = _context;
    if (ctx == null || !ctx.mounted) return;
    if (SosState.instance.hasActiveSos && beforeSos == 0) {
      AppToast.show(
        ctx,
        message: 'SOS is active — responders have been notified',
        kind: AppToastKind.info,
      );
    }
  }
}

/// Starts [SessionPoller] while this widget is mounted (used inside shells).
class SessionPollerScope extends StatefulWidget {
  const SessionPollerScope({super.key, required this.child});

  final Widget child;

  @override
  State<SessionPollerScope> createState() => _SessionPollerScopeState();
}

class _SessionPollerScopeState extends State<SessionPollerScope> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        SessionPoller.instance.attach(context);
        // Opt-in WebSocket channel (§7.1). No-op unless MCARE_WS_URL +
        // MCARE_WS_APP_KEY are set — REST polling continues either way.
        RealtimeChannel.instance.attach();
      }
    });
  }

  @override
  void dispose() {
    SessionPoller.instance.detach();
    RealtimeChannel.instance.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

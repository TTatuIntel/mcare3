import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/user_role.dart';
import '../models/vital.dart';
import '../state/staff_state.dart';
import 'app_dialog.dart';
import 'app_icons.dart';
import 'sos_alert_popup.dart';

/// App-wide listener that pops a popup the instant an SOS or critical
/// vital alert lands for a patient inside the current user's scope.
class CriticalEventOverlay extends StatefulWidget {
  const CriticalEventOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<CriticalEventOverlay> createState() => _CriticalEventOverlayState();
}

class _CriticalEventOverlayState extends State<CriticalEventOverlay> {
  final Set<String> _seenSos = {};
  final Set<String> _seenAlerts = {};
  bool _seeded = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    StaffState.instance.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    StaffState.instance.removeListener(_check);
    super.dispose();
  }

  Set<String> _scope() {
    final user = AuthState.instance.user;
    if (user == null) return {};
    switch (user.role) {
      case UserRole.doctor:
        return StaffState.instance
            .assignedPatientsForDoctor()
            .map((p) => p.id)
            .toSet();
      case UserRole.admin:
      case UserRole.mcareAssistant:
        return StaffState.instance.patients.map((p) => p.id).toSet();
      default:
        return {};
    }
  }

  UserRole? _staffRole() {
    final user = AuthState.instance.user;
    if (user == null) return null;
    switch (user.role) {
      case UserRole.doctor:
      case UserRole.admin:
      case UserRole.mcareAssistant:
        return user.role;
      default:
        return null;
    }
  }

  void _check() {
    if (!mounted) return;
    final role = _staffRole();
    if (role == null) return;
    final scope = _scope();

    final sos = StaffState.instance.patientSos
        .where((e) => e.isActive && scope.contains(e.patientId))
        .toList();
    final criticalAlerts = StaffState.instance.alerts
        .where((a) =>
            !a.acknowledged &&
            a.severity == RiskLevel.critical &&
            scope.contains(a.patientId))
        .toList();

    if (!_seeded) {
      _seenSos.addAll(sos.map((e) => e.id));
      _seenAlerts.addAll(criticalAlerts.map((a) => a.id));
      _seeded = true;
      return;
    }

    if (_showing) return;

    final newSos = sos.where((e) => !_seenSos.contains(e.id)).toList();
    if (newSos.isNotEmpty) {
      for (final e in newSos) {
        _seenSos.add(e.id);
      }
      SosAlertPopup.maybeShow(
        context,
        scopePatientIds: scope,
        routeFor: role,
      );
      return;
    }

    for (final a in criticalAlerts) {
      if (!_seenAlerts.contains(a.id)) {
        _seenAlerts.add(a.id);
        _showVitalPopup(role: role, alert: a);
        return;
      }
    }
  }

  Future<void> _showVitalPopup({
    required UserRole role,
    required StaffAlert alert,
  }) async {
    final navState = Navigator.maybeOf(context, rootNavigator: true);
    if (navState == null) return;
    _showing = true;
    final confirmed = await AppDialog.confirm(
      navState.context,
      title: 'Critical · ${alert.vital.label}',
      message: '${alert.patientName} · ${alert.value} ${alert.vital.unit}. '
          'Threshold breach — review now.',
      confirmLabel: 'Open patient',
      cancelLabel: 'Acknowledge',
      danger: true,
      icon: AppIcons.alert,
    );
    _showing = false;
    if (confirmed == true) {
      final route = switch (role) {
        UserRole.doctor => RouteNames.doctorPatientChart,
        UserRole.admin => RouteNames.adminUserDetail,
        UserRole.mcareAssistant => RouteNames.assistantAssignments,
        _ => RouteNames.doctorPatientChart,
      };
      navState.pushNamed(route, arguments: alert.patientId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

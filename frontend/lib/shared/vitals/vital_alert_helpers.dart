import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/sos_navigation.dart';
import '../models/vital.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';

/// Shared caseload alert snapshot — one source of truth for KPI cards,
/// inbox headers, and overview tiles.
class CaseloadAlertSummary {
  const CaseloadAlertSummary({
    required this.openAlerts,
    required this.activeSos,
    required this.criticalCount,
    required this.topAlert,
    required this.topSos,
  });

  final List<StaffAlert> openAlerts;
  final List<StaffPatientSos> activeSos;
  final int criticalCount;
  final StaffAlert? topAlert;
  final StaffPatientSos? topSos;

  int get openCount => openAlerts.length + activeSos.length;

  bool get shouldPulse => criticalCount > 0 || activeSos.isNotEmpty;

  String get kpiDetail {
    if (openCount == 0) return 'All clear';

    final sos = topSos;
    if (sos != null) {
      final first = (sos.patientName ?? 'Patient').split(' ').first;
      return criticalCount > 1
          ? '$criticalCount critical · $first · SOS'
          : '$first · SOS';
    }

    final top = topAlert;
    if (top == null) return '$openCount open';

    final first = top.patientName.split(' ').first;
    final valueSuffix = top.value.trim().isEmpty
        ? ''
        : ' · ${top.value.trim()}';

    if (top.kind == 'sos') {
      return criticalCount > 0
          ? '$criticalCount critical · $first · SOS$valueSuffix'
          : '$first · SOS$valueSuffix';
    }

    if (criticalCount > 0) {
      return '$criticalCount critical · $first · ${top.vital.shortLabel}$valueSuffix';
    }
    return '$first · ${top.vital.label}$valueSuffix';
  }

  Color kpiAccent({Color muted = AppColors.textMutedAA}) {
    if (activeSos.isNotEmpty || criticalCount > 0) return AppColors.critical;
    if (openCount > 0) return AppColors.warning;
    return muted;
  }

  /// Highest-priority alert id when the KPI should drill into alert detail.
  String? get primaryAlertId => topSos == null ? topAlert?.id : null;

  String? get primarySosPatientId => topSos?.patientId;

  String? get primarySosEventId => topSos?.id;
}

/// Drill into the highest-priority open alert from a KPI card.
void openCaseloadAlertPrimary(
  BuildContext context,
  CaseloadAlertSummary summary,
) {
  final sosPatientId = summary.primarySosPatientId;
  if (sosPatientId != null) {
    SosNavigation.openRespond(
      context,
      patientId: sosPatientId,
      eventId: summary.primarySosEventId,
    );
    return;
  }
  final alertId = summary.primaryAlertId;
  if (alertId != null) {
    Navigator.of(
      context,
    ).pushNamed(RouteNames.doctorAlertDetail, arguments: alertId);
    return;
  }
  Navigator.of(context).pushNamed(RouteNames.doctorAlerts);
}

/// Sort alerts by severity (critical first) then recency.
List<StaffAlert> sortAlertsByUrgency(Iterable<StaffAlert> alerts) {
  final copy = List<StaffAlert>.from(alerts);
  copy.sort((a, b) {
    final c = a.severity.index.compareTo(b.severity.index);
    if (c != 0) return c;
    return b.createdAt.compareTo(a.createdAt);
  });
  return copy;
}

extension StaffStateCaseloadAlerts on StaffState {
  List<StaffAlert> openAlertsForCaseload({Set<String>? patientIds}) {
    final ids =
        patientIds ?? assignedPatientsForDoctor().map((p) => p.id).toSet();
    return alerts
        .where(
          (a) => !a.acknowledged && !a.resolved && ids.contains(a.patientId),
        )
        .toList();
  }

  List<StaffPatientSos> activeSosForCaseload({Set<String>? patientIds}) {
    final ids =
        patientIds ?? assignedPatientsForDoctor().map((p) => p.id).toSet();
    return patientSos
        .where((e) => ids.contains(e.patientId) && e.isActive)
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
  }

  CaseloadAlertSummary caseloadAlertSummary({Set<String>? patientIds}) {
    final open = openAlertsForCaseload(patientIds: patientIds);
    final activeSos = activeSosForCaseload(patientIds: patientIds);
    final sorted = sortAlertsByUrgency(open);
    final criticalAlerts = open
        .where((a) => a.severity == RiskLevel.critical)
        .length;
    final critical = criticalAlerts + activeSos.length;

    final topSos = activeSos.isEmpty ? null : activeSos.first;
    final topAlert = sorted.isEmpty ? null : sorted.first;

    return CaseloadAlertSummary(
      openAlerts: open,
      activeSos: activeSos,
      criticalCount: critical,
      topAlert: topAlert,
      topSos: topSos,
    );
  }

  /// Every built-in vital supported by the patient tracking experience.
  ///
  /// Catalog enablement controls defaults and alert configuration. It must
  /// not prevent a doctor from assigning a supported vital to a patient.
  List<VitalKey> enabledBuiltinVitals() {
    return VitalKey.values;
  }
}

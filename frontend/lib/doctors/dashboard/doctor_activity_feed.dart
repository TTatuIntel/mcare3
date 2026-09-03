import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../patients/doctor_patient_section.dart';

/// One entry in the doctor's chronological activity feed. Unlike
/// [DoctorActionItem] (urgent + prioritized), every activity logged by an
/// assigned patient surfaces here, latest first.
class DoctorActivityItem {
  const DoctorActivityItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.pill,
    required this.pillColor,
    required this.at,
    required this.patientId,
    required this.section,
    this.urgent = false,
    this.alertId,
    this.overrideRouteName,
    this.overrideRouteArguments,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String pill;
  final Color pillColor;
  final DateTime at;
  final String patientId;
  final DoctorPatientSection section;
  final bool urgent;
  final String? alertId;
  final String? overrideRouteName;
  final Object? overrideRouteArguments;

  String get routeName {
    if (overrideRouteName != null) return overrideRouteName!;
    if (alertId != null) return RouteNames.doctorAlertDetail;
    return RouteNames.doctorPatientChart;
  }

  Object? get routeArguments {
    if (overrideRouteName != null) return overrideRouteArguments;
    if (alertId != null) return alertId;
    return {'patientId': patientId, 'section': section.name};
  }
}

class DoctorActivityFeed {
  DoctorActivityFeed._();

  /// Look back this far when collecting activity for the dashboard preview.
  /// Older items are pruned so the feed stays focused on what's actionable.
  static const lookbackDays = 7;
  static const dashboardPreviewLimit = 8;

  static List<DoctorActivityItem> collect({
    required BuildContext context,
    required Set<String> assignedIds,
    required StaffPatient? Function(String id) patientName,
  }) {
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: lookbackDays));
    final items = <DoctorActivityItem>[];

    for (final e in StaffState.instance.patientSos) {
      if (!assignedIds.contains(e.patientId)) continue;
      if (e.triggeredAt.isBefore(cutoff)) continue;
      final name = patientName(e.patientId)?.name ?? 'Patient';
      items.add(
        DoctorActivityItem(
          icon: AppIcons.sos,
          iconColor: AppColors.critical,
          title: '$name · SOS ${e.isActive ? 'triggered' : 'resolved'}',
          subtitle:
              '${e.kindLabel}${e.locationLabel != null ? ' · ${e.locationLabel}' : ''} · ${_relative(e.triggeredAt)}',
          pill: e.isActive ? 'Respond' : 'Resolved',
          pillColor: e.isActive ? AppColors.critical : AppColors.success,
          at: e.triggeredAt,
          patientId: e.patientId,
          section: DoctorPatientSection.sos,
          urgent: e.isActive,
          overrideRouteName: e.isActive ? RouteNames.doctorPatientChart : null,
          overrideRouteArguments: e.isActive
              ? {
                  'patientId': e.patientId,
                  'section': DoctorPatientSection.sos.name,
                  'sosRespond': true,
                  'eventId': e.id,
                }
              : null,
        ),
      );
    }

    for (final a in StaffState.instance.alerts) {
      if (!assignedIds.contains(a.patientId)) continue;
      if (a.createdAt.isBefore(cutoff)) continue;
      final isSos = a.kind == 'sos';
      final color = a.severity == RiskLevel.critical
          ? AppColors.critical
          : a.severity == RiskLevel.warning
          ? AppColors.warning
          : AppColors.info;
      String pill;
      if (a.resolved) {
        pill = 'Resolved';
      } else if (a.acknowledged) {
        pill = 'Acknowledged';
      } else if (a.severity == RiskLevel.critical) {
        pill = 'Critical';
      } else {
        pill = 'Review';
      }
      items.add(
        DoctorActivityItem(
          icon: isSos ? AppIcons.sos : a.vital.icon,
          iconColor: a.resolved ? AppPalette.textMuted(context) : color,
          title: isSos
              ? '${a.patientName} · SOS alert'
              : '${a.patientName} · ${a.vital.label} alert',
          subtitle: '${a.value} · ${_relative(a.createdAt)}',
          pill: pill,
          pillColor: a.resolved ? AppPalette.textMuted(context) : color,
          at: a.createdAt,
          patientId: a.patientId,
          section: DoctorPatientSection.alerts,
          alertId: a.id,
          urgent: !a.acknowledged && !a.resolved,
        ),
      );
    }

    for (final v in StaffState.instance.patientVitalReadings) {
      if (!assignedIds.contains(v.patientId)) continue;
      if (v.recordedAt.isBefore(cutoff)) continue;
      // If a non-normal reading already has an unresolved alert, the alert
      // row above is the actionable surface — skip the duplicate here.
      if (v.risk != RiskLevel.normal) {
        final covered = StaffState.instance.alerts.any(
          (a) =>
              a.patientId == v.patientId && a.vital == v.vital && !a.resolved,
        );
        if (covered) continue;
      }
      final name = patientName(v.patientId)?.name ?? 'Patient';
      final color = v.risk == RiskLevel.critical
          ? AppColors.critical
          : v.risk == RiskLevel.warning
          ? AppColors.warning
          : AppColors.success;
      items.add(
        DoctorActivityItem(
          icon: v.vital.icon,
          iconColor: color,
          title: '$name · ${v.vital.label}',
          subtitle: '${v.value} · ${_relative(v.recordedAt)}',
          pill: v.risk.label,
          pillColor: color,
          at: v.recordedAt,
          patientId: v.patientId,
          section: DoctorPatientSection.vitals,
          urgent: v.risk == RiskLevel.critical,
        ),
      );
    }

    for (final p in StaffState.instance.prescriptions) {
      if (!assignedIds.contains(p.patientId)) continue;
      if (p.issuedAt.isBefore(cutoff)) continue;
      items.add(
        DoctorActivityItem(
          icon: AppIcons.prescription,
          iconColor: AppColors.info,
          title: '${p.patientName} · Rx ${p.drug}',
          subtitle: '${p.dosage} · ${p.frequency} · ${_relative(p.issuedAt)}',
          pill: p.status,
          pillColor: AppColors.info,
          at: p.issuedAt,
          patientId: p.patientId,
          section: DoctorPatientSection.prescriptions,
        ),
      );
    }

    for (final a in StaffState.instance.appointments) {
      final pid = a.patientId;
      if (pid == null || !assignedIds.contains(pid)) continue;
      // Show recent past (up to lookbackDays) and upcoming (within 30 days).
      final diff = a.startAt.difference(now);
      if (diff.isNegative && a.startAt.isBefore(cutoff)) continue;
      if (!diff.isNegative && diff.inDays > 30) continue;
      final upcoming = !diff.isNegative;
      final imminent = upcoming && diff.inHours < 6;
      items.add(
        DoctorActivityItem(
          icon: AppIcons.appointment,
          iconColor: AppColors.success,
          title: '${a.patientName} · ${a.kind}',
          subtitle: upcoming
              ? '${DateFormat.MMMEd().add_jm().format(a.startAt)} · in ${_friendlyDiff(diff)}'
              : '${DateFormat.MMMEd().add_jm().format(a.startAt)} · ${_relative(a.startAt)}',
          pill: upcoming ? (imminent ? 'Soon' : 'Upcoming') : 'Past',
          pillColor: upcoming
              ? AppColors.success
              : AppPalette.textMuted(context),
          at: a.startAt,
          patientId: pid,
          section: DoctorPatientSection.appointments,
          urgent: imminent,
        ),
      );
    }

    for (final d in StaffState.instance.patientDocuments) {
      if (!assignedIds.contains(d.patientId)) continue;
      if (d.uploadedAt.isBefore(cutoff)) continue;
      final name = patientName(d.patientId)?.name ?? 'Patient';
      items.add(
        DoctorActivityItem(
          icon: AppIcons.document,
          iconColor: AppColors.info,
          title: '$name · uploaded ${d.title}',
          subtitle: '${d.category} · ${_relative(d.uploadedAt)}',
          pill: 'Document',
          pillColor: AppColors.info,
          at: d.uploadedAt,
          patientId: d.patientId,
          section: DoctorPatientSection.documents,
        ),
      );
    }

    for (final r in StaffState.instance.reports) {
      if (r.createdAt.isBefore(cutoff)) continue;
      StaffPatient? patient;
      for (final p in StaffState.instance.patients) {
        if (p.name == r.patientName && assignedIds.contains(p.id)) {
          patient = p;
          break;
        }
      }
      if (patient == null) continue;
      items.add(
        DoctorActivityItem(
          icon: AppIcons.report,
          iconColor: AppColors.info,
          title: '${r.patientName} · ${r.title}',
          subtitle:
              '${r.published ? 'Published' : 'Draft'} · ${_relative(r.createdAt)}',
          pill: r.published ? 'Report' : 'Draft',
          pillColor: r.published ? AppColors.success : AppColors.warning,
          at: r.createdAt,
          patientId: patient.id,
          section: DoctorPatientSection.reports,
        ),
      );
    }

    items.sort((a, b) {
      if (a.urgent != b.urgent) return a.urgent ? -1 : 1;
      return b.at.compareTo(a.at);
    });
    return items;
  }

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.isNegative) {
      final ahead = -diff.inMinutes;
      if (ahead < 60) return 'in ${ahead}m';
      final hAhead = -diff.inHours;
      if (hAhead < 24) return 'in ${hAhead}h';
      return DateFormat.MMMd().format(d);
    }
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(d);
  }

  static String _friendlyDiff(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

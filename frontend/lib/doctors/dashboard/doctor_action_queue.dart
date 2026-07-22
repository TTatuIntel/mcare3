import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../patients/doctor_patient_section.dart';

/// One prioritized item in the doctor's live action queue.
class DoctorActionItem {
  const DoctorActionItem({
    required this.priority,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.pill,
    required this.pillColor,
    required this.at,
    required this.patientId,
    required this.section,
    this.alertId,
    this.overrideRouteName,
    this.overrideRouteArguments,
  });

  final int priority;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String pill;
  final Color pillColor;
  final DateTime at;
  final String patientId;
  final DoctorPatientSection section;
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
    return {
      'patientId': patientId,
      'section': section.name,
    };
  }
}

class DoctorActionQueue {
  DoctorActionQueue._();

  static const previewHours = 12;
  static const dashboardPreviewLimit = 5;

  static List<DoctorActionItem> collect({
    required Set<String> assignedIds,
    required StaffPatient? Function(String id) patientName,
  }) {
    final now = DateTime.now();
    final items = <DoctorActionItem>[];

    for (final e in StaffState.instance.patientSos) {
      if (!assignedIds.contains(e.patientId) || !e.isActive) continue;
      final name = patientName(e.patientId)?.name ?? 'Patient';
      items.add(DoctorActionItem(
        priority: 0,
        icon: AppIcons.sos,
        iconColor: AppColors.critical,
        title: '$name · SOS',
        subtitle: e.locationLabel ?? e.kindLabel,
        pill: 'Respond',
        pillColor: AppColors.critical,
        at: e.triggeredAt,
        patientId: e.patientId,
        section: DoctorPatientSection.sos,
        overrideRouteName: RouteNames.doctorPatientChart,
        overrideRouteArguments: {
          'patientId': e.patientId,
          'section': DoctorPatientSection.sos.name,
          'sosRespond': true,
          'eventId': e.id,
        },
      ));
    }

    for (final a in StaffState.instance.alerts) {
      if (!assignedIds.contains(a.patientId) || a.acknowledged) continue;
      final severity = a.severity == RiskLevel.critical ? 1 : 5;
      items.add(DoctorActionItem(
        priority: severity,
        icon: a.vital.icon,
        iconColor: a.severity == RiskLevel.critical
            ? AppColors.critical
            : AppColors.warning,
        title: '${a.patientName} · ${a.vital.label}',
        subtitle: '${a.value} · ${_relative(a.createdAt)}',
        pill: a.severity == RiskLevel.critical ? 'Critical' : 'Review',
        pillColor: a.severity == RiskLevel.critical
            ? AppColors.critical
            : AppColors.warning,
        at: a.createdAt,
        patientId: a.patientId,
        section: DoctorPatientSection.alerts,
        alertId: a.id,
      ));
    }

    for (final v in StaffState.instance.patientVitalReadings) {
      if (!assignedIds.contains(v.patientId)) continue;
      if (now.difference(v.recordedAt).inHours > previewHours) continue;
      final isNormal = v.risk == RiskLevel.normal;
      if (!isNormal) {
        final hasAlert = StaffState.instance.alerts.any((a) =>
            a.patientId == v.patientId &&
            a.vital == v.vital &&
            !a.acknowledged);
        if (hasAlert) continue;
      }

      final name = patientName(v.patientId)?.name ?? 'Patient';
      final color = v.risk == RiskLevel.critical
          ? AppColors.critical
          : v.risk == RiskLevel.warning
              ? AppColors.warning
              : AppColors.info;
      items.add(DoctorActionItem(
        priority: v.risk == RiskLevel.critical
            ? 3
            : v.risk == RiskLevel.warning
                ? 4
                : 7,
        icon: v.vital.icon,
        iconColor: color,
        title: isNormal
            ? '$name · ${v.vital.label} logged'
            : '$name · New ${v.vital.label}',
        subtitle: '${v.value} · ${_relative(v.recordedAt)}',
        pill: isNormal ? 'Logged' : 'Vitals',
        pillColor: color,
        at: v.recordedAt,
        patientId: v.patientId,
        section: DoctorPatientSection.vitals,
      ));
    }

    for (final a in StaffState.instance.appointments) {
      if (a.patientId == null || !assignedIds.contains(a.patientId)) continue;
      final diff = a.startAt.difference(now);
      // Surface today's appointments (recent past up to 30 min) and anything
      // starting within the next 24 hours so reminders show up live.
      if (diff.inMinutes < -30) continue;
      if (diff.inHours > 24) continue;
      final isToday = _isToday(a.startAt);
      items.add(DoctorActionItem(
        priority: isToday ? 6 : 9,
        icon: AppIcons.appointment,
        iconColor: AppColors.success,
        title: '${a.patientName} · ${a.kind}',
        subtitle:
            '${isToday ? DateFormat.jm().format(a.startAt) : DateFormat.MMMEd().add_jm().format(a.startAt)}${a.notes != null ? ' · ${a.notes}' : ''}',
        pill: isToday ? 'Today' : 'Upcoming',
        pillColor: AppColors.success,
        at: a.startAt,
        patientId: a.patientId!,
        section: DoctorPatientSection.appointments,
      ));
    }

    // Recently issued prescriptions / reminders assigned to the patient.
    for (final p in StaffState.instance.prescriptions) {
      if (!assignedIds.contains(p.patientId)) continue;
      if (now.difference(p.issuedAt).inHours > 24) continue;
      items.add(DoctorActionItem(
        priority: 8,
        icon: AppIcons.prescription,
        iconColor: AppColors.info,
        title: '${p.patientName} · Rx ${p.drug}',
        subtitle:
            '${p.dosage} · ${p.frequency} · ${_relative(p.issuedAt)}',
        pill: 'Reminder',
        pillColor: AppColors.info,
        at: p.issuedAt,
        patientId: p.patientId,
        section: DoctorPatientSection.prescriptions,
      ));
    }

    items.sort((a, b) {
      final p = a.priority.compareTo(b.priority);
      if (p != 0) return p;
      return b.at.compareTo(a.at);
    });

    return items;
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  static String _relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat.MMMd().format(d);
  }
}

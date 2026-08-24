import 'package:flutter/material.dart';

import '../../models/user_dossier.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_icons.dart';
import 'dossier_blocks.dart';

/// Patient-facing halves of the dossier: the Overview and Clinical segments.
///
/// Everything the platform holds on a patient appears somewhere across these
/// two segments — health profile, vitals, medications, meals, progress, care
/// team, appointments, documents, alerts, SOS, and requests — so an admin
/// never has to open four screens before acting.

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

List<Widget> buildPatientOverviewSections(BuildContext context, UserDossier d) {
  final clinical = d.clinical;
  final progress = d.progress;
  final health = clinical?.health;

  return [
    if (progress != null) _ProgressCard(progress: progress),
    DossierCard(
      title: 'Health profile',
      icon: AppIcons.vitals,
      trailing: clinical?.hasHealthProfile == true ? null : 'Not completed',
      emptyMessage: 'The patient has not completed their health profile.',
      children: health == null
          ? const []
          : [
              DossierRow(
                label: 'Date of birth',
                value: _dobLine(health['date_of_birth']),
              ),
              DossierRow(
                label: 'Gender',
                value: dossierHumanize(_s(health['gender'])),
              ),
              DossierRow(label: 'Blood type', value: _s(health['blood_type'])),
              DossierRow(
                label: 'Height / Weight',
                value: _heightWeight(health),
              ),
              DossierRow(label: 'BMI', value: _bmi(health), emphasise: true),
              DossierRow(label: 'Address', value: _s(health['address'])),
              DossierRow(
                label: 'Conditions',
                value: _list(health['chronic_conditions'], 'None recorded'),
              ),
              DossierRow(
                label: 'Allergies',
                value: health['no_known_allergies'] == true
                    ? 'None known'
                    : _list(health['allergies'], 'Not recorded'),
              ),
              DossierRow(
                label: 'Self-reported meds',
                value: health['no_current_medications'] == true
                    ? 'None'
                    : _list(health['current_medications'], 'Not recorded'),
              ),
              DossierRow(
                label: 'Location sharing',
                value: health['location_consent'] == true
                    ? 'Consented'
                    : 'Not consented',
              ),
            ],
    ),
    DossierCard(
      title: 'Assigned vitals',
      icon: AppIcons.vitals,
      trailing: '${clinical?.assignedVitals.length ?? 0}',
      emptyMessage: 'No vitals assigned yet.',
      children: [
        if (clinical != null && clinical.assignedVitals.isNotEmpty)
          DossierChips(
            labels: clinical.vitalsSummary
                .where((v) => v.assigned)
                .map((v) => v.label)
                .toList(),
            color: AppColors.bpPurple,
          ),
      ],
    ),
    DossierCard(
      title: 'Care team',
      icon: AppIcons.careTeam,
      trailing: '${clinical?.careTeam.length ?? 0}',
      emptyMessage: 'No provider assigned — this patient is unattached.',
      children: [
        for (final a in clinical?.careTeam ?? const <Map<String, dynamic>>[])
          DossierRecordRow(
            icon: AppIcons.careTeam,
            iconColor: AppColors.doctorGreen,
            title: _s(a['provider_name']) ?? 'Provider',
            subtitle: [
              _s(a['provider_specialty']),
              if (_s(a['assigned_reason']) != null) _s(a['assigned_reason']),
            ].whereType<String>().join(' · '),
            badge: dossierHumanize(_s(a['role'])),
            badgeColor: _s(a['ended_at']) == null
                ? AppColors.success
                : AppColors.textMutedAA,
            meta: dossierDate(_d(a['assigned_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Emergency contacts',
      icon: AppIcons.sos,
      trailing: '${clinical?.emergencyContacts.length ?? 0}',
      emptyMessage: 'No next of kin recorded.',
      children: [
        for (final c
            in clinical?.emergencyContacts ?? const <Map<String, dynamic>>[])
          DossierRecordRow(
            icon: AppIcons.phone,
            iconColor: AppColors.critical,
            title: _s(c['name']) ?? 'Contact',
            subtitle: [
              dossierHumanize(_s(c['relationship'])),
              _s(c['phone']),
              _s(c['email']),
            ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
          ),
      ],
    ),
  ];
}

/// Adherence, logging streak, and engagement — the "is this patient actually
/// doing the programme" answer, above the raw records.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});
  final DossierProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final score = progress.engagementScore;
    final color = score >= 70
        ? AppColors.success
        : score >= 40
            ? AppColors.warning
            : AppColors.critical;

    final stale = (progress.daysSinceLastReading ?? 0) >= 3;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: score / 100,
                          strokeWidth: 5,
                          backgroundColor: color.withValues(alpha: 0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(color),
                        ),
                      ),
                      Text(
                        '$score',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Engagement',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        progress.lastReadingAt == null
                            ? 'No readings logged yet.'
                            : 'Last reading '
                                '${dossierRelative(progress.lastReadingAt!)}'
                                '${stale ? ' — falling behind' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: stale
                              ? AppColors.critical
                              : AppPalette.ink(context),
                          fontWeight:
                              stale ? FontWeight.w700 : FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: color.withValues(alpha: 0.2)),
            const SizedBox(height: AppSpacing.sm),
            DossierRow(
              label: 'Adherence (30d)',
              value: progress.adherencePercent == null
                  ? 'No scheduled doses'
                  : '${progress.adherencePercent}%  '
                      '(${progress.dosesTaken30d}/${progress.dosesDue30d} taken)',
            ),
            DossierRow(
              label: 'Doses missed',
              value: '${progress.dosesMissed30d}',
              valueColor:
                  progress.dosesMissed30d > 0 ? AppColors.critical : null,
            ),
            DossierRow(
              label: 'Readings',
              value: '${progress.readings7d} in 7d · '
                  '${progress.readings30d} in 30d',
            ),
            DossierRow(
              label: 'Logging streak',
              value: '${progress.loggingStreakDays} '
                  'day${progress.loggingStreakDays == 1 ? '' : 's'}',
            ),
            DossierRow(
              label: 'Appointments',
              value: '${progress.appointmentsKept} kept · '
                  '${progress.appointmentsMissed} missed',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Clinical
// ---------------------------------------------------------------------------

List<Widget> buildClinicalSections(BuildContext context, UserDossier d) {
  final c = d.clinical;
  if (c == null) {
    return const [
      DossierCard(
        title: 'Clinical record',
        icon: AppIcons.vitals,
        emptyMessage: 'No clinical record for this account.',
        children: [],
      ),
    ];
  }

  return [
    DossierCard(
      title: 'Vitals',
      icon: AppIcons.vitals,
      trailing: '${c.vitalsSummary.length} tracked',
      emptyMessage: 'No readings recorded.',
      children: [
        for (final v in c.vitalsSummary)
          DossierRecordRow(
            icon: v.trend == 'up'
                ? AppIcons.trendUp
                : v.trend == 'down'
                    ? AppIcons.trendDown
                    : AppIcons.trend,
            iconColor: dossierRiskColor(v.latestRisk),
            title: '${v.label}${v.assigned ? '' : '  (not assigned)'}',
            subtitle: v.latestAt == null
                ? '${v.readingsTotal} reading(s) on file'
                : 'Last ${dossierRelative(v.latestAt!)} · '
                    '${v.readings30d} in 30d',
            badge: v.latestValue ?? '—',
            badgeColor: dossierRiskColor(v.latestRisk),
          ),
      ],
    ),
    DossierCard(
      title: 'Medications & prescriptions',
      icon: AppIcons.medication,
      trailing: '${c.activeMedications} active',
      emptyMessage: 'No medications on file.',
      children: [
        for (final m in c.medications)
          DossierRecordRow(
            icon: AppIcons.medication,
            iconColor: AppColors.glucoseAmber,
            title: [
              _s(m['name']) ?? 'Medication',
              if (_s(m['dosage']) != null) _s(m['dosage']),
            ].whereType<String>().join(' · '),
            subtitle: [
              _s(m['frequency']),
              if (_s(m['prescribed_by_name']) != null)
                'by ${_s(m['prescribed_by_name'])}',
              if (_s(m['instructions']) != null) _s(m['instructions']),
            ].whereType<String>().join(' · '),
            badge: m['active'] == true ? 'Active' : 'Ended',
            badgeColor: m['active'] == true
                ? AppColors.success
                : AppColors.textMutedAA,
            meta: dossierDate(_d(m['start_date'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Meal plans & nutrition',
      icon: AppIcons.meals,
      trailing: '${c.mealPlans.length}',
      emptyMessage: 'No meal plans assigned.',
      children: [
        for (final m in c.mealPlans)
          DossierRecordRow(
            icon: AppIcons.meals,
            iconColor: AppColors.respGreen,
            title: _s(m['title']) ?? 'Meal',
            subtitle: [
              dossierHumanize(_s(m['meal_type'])),
              _macros(m),
              if (_s(m['assigned_by']) != null) 'by ${_s(m['assigned_by'])}',
            ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
            meta: dossierDate(_d(m['assigned_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Appointments',
      icon: AppIcons.appointment,
      trailing: '${c.appointments.length}',
      emptyMessage: 'No appointments recorded.',
      children: [
        for (final a in c.appointments.take(15))
          DossierRecordRow(
            icon: AppIcons.appointment,
            iconColor: AppColors.bpPurple,
            title: _s(a['doctor_name']) ?? 'Appointment',
            subtitle: [
              dossierHumanize(_s(a['type'])),
              _s(a['reason']),
              _s(a['cancellation_reason']),
            ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
            badge: dossierHumanize(_s(a['status'])),
            badgeColor: _appointmentColor(_s(a['status'])),
            meta: dossierDateTime(_d(a['scheduled_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Vital alerts',
      icon: AppIcons.alert,
      trailing: '${c.alerts.length}',
      emptyMessage: 'No alerts raised.',
      children: [
        for (final a in c.alerts.take(12))
          DossierRecordRow(
            icon: AppIcons.alert,
            iconColor: _s(a['kind']) == 'vital_critical'
                ? AppColors.critical
                : AppColors.warning,
            title: _s(a['title']) ?? 'Alert',
            subtitle: _s(a['body']),
            badge: a['read'] == true ? 'Read' : 'Unread',
            badgeColor: a['read'] == true
                ? AppColors.textMutedAA
                : AppColors.critical,
            meta: dossierDate(_d(a['created_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Emergency (SOS) events',
      icon: AppIcons.sos,
      trailing: '${c.sosEvents.length}',
      emptyMessage: 'No SOS events.',
      children: [
        for (final s in c.sosEvents.take(10))
          DossierRecordRow(
            icon: AppIcons.sos,
            iconColor: AppColors.critical,
            title: dossierHumanize(_s(s['kind'])).isEmpty
                ? 'Emergency'
                : dossierHumanize(_s(s['kind'])),
            subtitle: [
              _s(s['location_label']),
              _s(s['note']),
              if (_s(s['responded_by']) != null)
                'responder ${_s(s['responded_by'])}',
            ].whereType<String>().join(' · '),
            badge: dossierHumanize(_s(s['status'])),
            badgeColor: _s(s['status']) == 'resolved'
                ? AppColors.success
                : AppColors.critical,
            meta: dossierDateTime(_d(s['triggered_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Medical documents',
      icon: AppIcons.document,
      trailing: '${c.documents.length}',
      emptyMessage: 'No documents uploaded.',
      children: [
        for (final doc in c.documents.take(15))
          DossierRecordRow(
            icon: AppIcons.document,
            iconColor: AppColors.weightSlate,
            title: _s(doc['title']) ?? 'Document',
            subtitle: [
              dossierHumanize(_s(doc['category'])),
              _s(doc['uploaded_by']),
              _s(doc['description']),
            ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
            badge: doc['has_file'] == true ? null : 'Missing file',
            badgeColor: AppColors.warning,
            meta: dossierDate(_d(doc['uploaded_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Clinical notes & reports',
      icon: AppIcons.report,
      trailing: '${c.reports.length}',
      emptyMessage: 'No reports written.',
      children: [
        for (final r in c.reports.take(12))
          DossierRecordRow(
            icon: AppIcons.report,
            iconColor: AppColors.doctorGreen,
            title: _s(r['title']) ?? 'Report',
            subtitle: _s(r['author_name']),
            badge: r['published'] == true ? 'Published' : 'Draft',
            badgeColor: r['published'] == true
                ? AppColors.success
                : AppColors.textMutedAA,
            meta: dossierDate(_d(r['created_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Care requests',
      icon: AppIcons.careRequest,
      trailing: '${c.careRequests.length}',
      emptyMessage: 'No care requests.',
      children: [
        for (final r in c.careRequests.take(10))
          DossierRecordRow(
            icon: AppIcons.careRequest,
            iconColor: AppColors.info,
            title: _s(r['assigned_provider_name']) ??
                _s(r['provider_name']) ??
                'Provider request',
            subtitle: [
              _s(r['reason']),
              if (r['reassigned'] == true)
                're-routed from ${_s(r['provider_name'])}',
              _s(r['decision_note']),
            ].whereType<String>().join(' · '),
            badge: dossierHumanize(_s(r['status'])),
            badgeColor: switch (_s(r['status'])) {
              'approved' || 'accepted' => AppColors.success,
              'declined' || 'cancelled' => AppColors.critical,
              _ => AppColors.warning,
            },
            meta: dossierDate(_d(r['created_at'])),
          ),
      ],
    ),
    DossierCard(
      title: 'Support tickets',
      icon: AppIcons.support,
      trailing: '${c.supportTickets.length}',
      emptyMessage: 'No support tickets raised.',
      children: [
        for (final t in c.supportTickets.take(10))
          DossierRecordRow(
            icon: AppIcons.ticket,
            iconColor: AppColors.mcareAmber,
            title: _s(t['subject']) ?? 'Ticket',
            badge: dossierHumanize(_s(t['status'])),
            badgeColor: _s(t['status']) == 'open'
                ? AppColors.warning
                : AppColors.textMutedAA,
            meta: dossierDate(_d(t['created_at'])),
          ),
      ],
    ),
  ];
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

Color _appointmentColor(String? status) => switch (status) {
      'completed' => AppColors.success,
      'cancelled' || 'missed' || 'no_show' => AppColors.critical,
      _ => AppColors.info,
    };

String _macros(Map<String, dynamic> m) {
  final parts = <String>[
    if (m['calories'] != null) '${m['calories']} kcal',
    if (m['protein'] != null) 'P ${m['protein']}',
    if (m['carbs'] != null) 'C ${m['carbs']}',
    if (m['fat'] != null) 'F ${m['fat']}',
  ];
  return parts.join(' · ');
}

String? _dobLine(dynamic raw) {
  final dob = _d(raw);
  if (dob == null) return null;
  final now = DateTime.now();
  var age = now.year - dob.year;
  if (now.month < dob.month ||
      (now.month == dob.month && now.day < dob.day)) {
    age--;
  }
  return '${dossierDate(dob)}  ($age years)';
}

String? _heightWeight(Map<String, dynamic> h) {
  final height = _num(h['height_cm']);
  final weight = _num(h['weight_kg']);
  if (height == null && weight == null) return null;
  return [
    if (height != null) '${height.toStringAsFixed(0)} cm',
    if (weight != null) '${weight.toStringAsFixed(0)} kg',
  ].join(' · ');
}

String? _bmi(Map<String, dynamic> h) {
  final height = _num(h['height_cm']);
  final weight = _num(h['weight_kg']);
  if (height == null || weight == null || height <= 0 || weight <= 0) {
    return null;
  }
  final bmi = weight / ((height / 100) * (height / 100));
  final band = bmi < 18.5
      ? 'Underweight'
      : bmi < 25
          ? 'Healthy'
          : bmi < 30
              ? 'Overweight'
              : 'Obese';
  return '${bmi.toStringAsFixed(1)} ($band)';
}

String _list(dynamic raw, String fallback) {
  if (raw is! List || raw.isEmpty) return fallback;
  return raw.map((e) => '$e').where((e) => e.trim().isNotEmpty).join(', ');
}

String? _s(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _d(dynamic v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vital.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_icons.dart';

/// A truthful, compact clinical-context snapshot for staff popups.
///
/// The current staff API exposes vital readings, assigned meal plans,
/// prescriptions, and clinical notes. It does not expose meal completion,
/// dose-adherence, hydration, or activity events, so those gaps are stated
/// explicitly instead of presenting invented percentages.
class PatientThreeDaySummary extends StatelessWidget {
  const PatientThreeDaySummary({
    super.key,
    required this.patientId,
    this.highlightedVital,
  });

  final String patientId;
  final VitalKey? highlightedVital;

  @override
  Widget build(BuildContext context) {
    final staff = StaffState.instance;
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 2));
    final recentVitals = staff
        .vitalsForPatient(patientId)
        .where((reading) => !reading.recordedAt.isBefore(start))
        .toList();
    final highlighted = recentVitals.where(
      (reading) => reading.vital == highlightedVital,
    );
    final latest = highlighted.isNotEmpty
        ? highlighted.first
        : (recentVitals.isEmpty ? null : recentVitals.first);
    final criticalCount = recentVitals
        .where((reading) => reading.risk == RiskLevel.critical)
        .length;
    final meals = staff.mealPlansForPatient(patientId);
    final medications = staff
        .prescriptionsForPatient(patientId)
        .where((rx) => rx.status.toLowerCase() == 'active')
        .toList();
    final clinicalNote = staff.assignedVitalsNoteForPatient(patientId);
    final readingNotes = recentVitals
        .where((reading) => (reading.note ?? '').trim().isNotEmpty)
        .length;
    final noteCount = readingNotes + (clinicalNote == null ? 0 : 1);
    final range =
        '${DateFormat.MMMd().format(start)}–${DateFormat.MMMd().format(now)}';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient summary · past 3 days',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Verified clinical records only',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandIndigo.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(
                    color: AppColors.brandIndigo.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  range,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.brandIndigo,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.sm;
              final columns = constraints.maxWidth < 280 ? 1 : 2;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  _SummaryTile(
                    width: width,
                    icon: latest?.vital.icon ?? AppIcons.vitals,
                    color: latest?.risk.color ?? AppColors.spo2Blue,
                    label: 'Vitals',
                    value: latest == null
                        ? 'No readings'
                        : '${latest.vital.shortLabel} ${latest.value}',
                    detail: recentVitals.isEmpty
                        ? 'Nothing recorded in this period'
                        : '${recentVitals.length} readings · $criticalCount critical',
                  ),
                  _SummaryTile(
                    width: width,
                    icon: AppIcons.meals,
                    color: AppColors.success,
                    label: 'Meals',
                    value: meals.isEmpty
                        ? 'No plan on file'
                        : '${meals.length} ${meals.length == 1 ? 'plan' : 'plans'} on file',
                    detail: 'Completion is not tracked yet',
                  ),
                  _SummaryTile(
                    width: width,
                    icon: AppIcons.medication,
                    color: AppColors.brandIndigo,
                    label: 'Medications',
                    value: medications.isEmpty
                        ? 'No active prescription'
                        : '${medications.length} active ${medications.length == 1 ? 'prescription' : 'prescriptions'}',
                    detail: 'Dose adherence is not tracked yet',
                  ),
                  _SummaryTile(
                    width: width,
                    icon: AppIcons.activity,
                    color: AppColors.warning,
                    label: 'Activity & hydration',
                    value: 'No recent log',
                    detail: 'No connected record available',
                  ),
                  _SummaryTile(
                    width: width,
                    icon: AppIcons.notes,
                    color: AppColors.info,
                    label: 'Clinical notes',
                    value: noteCount == 0
                        ? 'No recent notes'
                        : '$noteCount ${noteCount == 1 ? 'note' : 'notes'} available',
                    detail: clinicalNote ?? 'From recent vital readings',
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.width,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(minHeight: 84),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppPalette.surface(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.ink(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontSize: 9.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

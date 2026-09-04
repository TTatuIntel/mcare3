import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/notification_item.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/vital_navigation.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/constants/route_names.dart';
import 'request_vital_report_sheet.dart';
import 'vital_reading_sheet.dart';

class Vitals7DayView extends StatelessWidget {
  const Vitals7DayView({super.key});

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientVitals,
      detachedNav: true,
      title: 'Past 7 days',
      subtitle: 'All tracked vitals on your phone',
      body: AnimatedBuilder(
        animation: Listenable.merge([
          VitalsState.instance,
          NotificationState.instance,
        ]),
        builder: (context, _) {
          final tracked = VitalsState.instance.tracked.toList();
          final readings = VitalsState.instance.recentReadings(days: 7);

          if (tracked.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 48),
              child: EmptyStateView(
                icon: AppIcons.vitals,
                title: 'No vitals tracked',
                message:
                    'Choose vitals to track, then your 7-day history appears here.',
                compact: true,
              ),
            );
          }

          final byVital = <VitalKey, List<VitalReading>>{};
          for (final r in readings) {
            byVital.putIfAbsent(r.vital, () => []).add(r);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: _SummaryStrip(
                  readingCount: readings.length,
                  vitalCount: byVital.length,
                  onRequestReport: () => RequestVitalReportSheet.show(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              StaggeredEntry(
                index: 1,
                child: SectionLabel(
                  title: 'By vital',
                  icon: AppIcons.vitals,
                  trailing: '${byVital.length} tracked',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (var i = 0; i < tracked.length; i++) ...[
                StaggeredEntry(
                  index: i + 2,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _VitalWeekCard(
                      vital: tracked[i],
                      readings: byVital[tracked[i]] ?? const [],
                    ),
                  ),
                ),
              ],
              if (readings.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                StaggeredEntry(
                  index: tracked.length + 2,
                  child: SectionLabel(
                    title: 'Timeline',
                    icon: AppIcons.time,
                    trailing: '${readings.length} readings',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: tracked.length + 3,
                  child: _TimelineCard(readings: readings.take(20).toList()),
                ),
              ],
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.readingCount,
    required this.vitalCount,
    required this.onRequestReport,
  });

  final int readingCount;
  final int vitalCount;
  final VoidCallback onRequestReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            readingCount == 0
                ? 'No readings in the last 7 days'
                : '$readingCount reading${readingCount == 1 ? '' : 's'} across $vitalCount vital${vitalCount == 1 ? '' : 's'}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppPalette.ink(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Need a longer history? Request a full report with a custom date range.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRequestReport,
              icon: const Icon(AppIcons.report, size: 16),
              label: const Text('Request vital report'),
            ),
          ),
        ],
      ),
    );
  }
}

class _VitalWeekCard extends StatelessWidget {
  const _VitalWeekCard({required this.vital, required this.readings});

  final VitalKey vital;
  final List<VitalReading> readings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = readings.isEmpty
        ? VitalsState.instance.latestOf(vital)
        : readings.first;
    final alert = NotificationState.instance.vitalAlertFor(vital);

    return GlassCard(
      frosted: true,
      onTap: () => openVitalDetail(context, vital),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: vital.accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(vital.icon, color: vital.accent, size: 21),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vital.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  readings.isEmpty
                      ? 'No readings this week'
                      : '${readings.length} reading${readings.length == 1 ? '' : 's'} · latest ${latest?.formatValue() ?? '—'} ${vital.unit}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          if (latest != null) RiskBadge(risk: latest.risk, dense: true),
          if (alert != null) ...[
            const SizedBox(width: 4),
            Icon(AppIcons.alert, size: 16, color: alert.kind.tint),
          ],
          const SizedBox(width: 4),
          Icon(
            AppIcons.chevronRight,
            size: 18,
            color: vital.accent.withOpacity(0.7),
          ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.readings});

  final List<VitalReading> readings;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (var i = 0; i < readings.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppPalette.border(context)),
            _TimelineRow(reading: readings[i]),
          ],
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.reading});

  final VitalReading reading;

  @override
  Widget build(BuildContext context) {
    final vital = reading.vital;
    return InkWell(
      onTap: () => VitalReadingSheet.show(context, reading: reading),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(vital.icon, size: 16, color: vital.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${vital.shortLabel} · ${reading.formatValue()} ${vital.unit}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    DateFormat.MMMEd().add_jm().format(reading.recordedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            RiskBadge(risk: reading.risk, dense: true),
          ],
        ),
      ),
    );
  }
}

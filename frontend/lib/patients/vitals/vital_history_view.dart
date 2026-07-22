import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
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
import 'request_vital_report_sheet.dart';
import 'vital_reading_sheet.dart';

const _historyDays = 7;

class VitalHistoryView extends StatefulWidget {
  const VitalHistoryView({super.key, required this.vital});
  final VitalKey vital;

  @override
  State<VitalHistoryView> createState() => _VitalHistoryViewState();
}

class _VitalHistoryViewState extends State<VitalHistoryView> {
  RiskLevel? _filter;

  List<VitalReading> _weekReadings() {
    final cutoff = DateTime.now().subtract(const Duration(days: _historyDays));
    return VitalsState.instance
        .forVital(widget.vital)
        .where((r) => r.recordedAt.isAfter(cutoff))
        .toList();
  }

  int _olderCount() {
    final cutoff = DateTime.now().subtract(const Duration(days: _historyDays));
    return VitalsState.instance
        .forVital(widget.vital)
        .where((r) => !r.recordedAt.isAfter(cutoff))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final vital = widget.vital;
    final weekStart = DateTime.now().subtract(const Duration(days: _historyDays));
    final rangeLabel =
        '${DateFormat.MMMd().format(weekStart)} – ${DateFormat.MMMd().format(DateTime.now())}';

    return PatientScaffold(
      currentRoute: RouteNames.patientVitals,
      detachedNav: true,
      title: '${vital.label} history',
      subtitle: 'Past 7 days on your phone',
      body: AnimatedBuilder(
        animation: VitalsState.instance,
        builder: (context, _) {
          var readings = _weekReadings();
          final olderCount = _olderCount();
          if (_filter != null) {
            readings = readings.where((r) => r.risk == _filter).toList();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: _WeekSummaryStrip(
                  vital: vital,
                  readingCount: _weekReadings().length,
                  rangeLabel: rangeLabel,
                  olderCount: olderCount,
                  onRequestReport: () => RequestVitalReportSheet.show(context),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: _FilterRow(value: _filter, onChanged: (v) => setState(() => _filter = v)),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 2,
                child: SectionLabel(
                  title: 'This week',
                  icon: AppIcons.records,
                  trailing: '${readings.length} shown',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (readings.isEmpty)
                StaggeredEntry(
                  index: 3,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: vital.icon,
                      title: 'No readings this week',
                      message: _filter != null
                          ? 'Try another filter or log a new reading.'
                          : 'Log a reading and it appears here for 7 days.',
                      actionLabel: _filter != null ? null : 'Request older report',
                      onAction: _filter != null
                          ? null
                          : () => RequestVitalReportSheet.show(context),
                      compact: true,
                    ),
                  ),
                )
              else
                StaggeredEntry(
                  index: 3,
                  child: _GroupedList(readings: readings),
                ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

class _WeekSummaryStrip extends StatelessWidget {
  const _WeekSummaryStrip({
    required this.vital,
    required this.readingCount,
    required this.rangeLabel,
    required this.olderCount,
    required this.onRequestReport,
  });

  final VitalKey vital;
  final int readingCount;
  final String rangeLabel;
  final int olderCount;
  final VoidCallback onRequestReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.accent;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(vital.icon, color: accent, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Past 7 days',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppPalette.ink(context),
                      ),
                    ),
                    Text(
                      '$rangeLabel · $readingCount reading${readingCount == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (olderCount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$olderCount older reading${olderCount == 1 ? '' : 's'} not shown here.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                height: 1.3,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRequestReport,
                icon: const Icon(AppIcons.report, size: 14),
                label: Text(
                  'Request vital report',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.value, required this.onChanged});
  final RiskLevel? value;
  final ValueChanged<RiskLevel?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(label: 'All', selected: value == null, onTap: () => onChanged(null)),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: 'Normal',
            color: AppColors.success,
            selected: value == RiskLevel.normal,
            onTap: () => onChanged(RiskLevel.normal),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: 'Watch',
            color: AppColors.warning,
            selected: value == RiskLevel.warning,
            onTap: () => onChanged(RiskLevel.warning),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: 'Critical',
            color: AppColors.critical,
            selected: value == RiskLevel.critical,
            onTap: () => onChanged(RiskLevel.critical),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: selected ? c : c.withOpacity(0.22)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : c,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.readings});
  final List<VitalReading> readings;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<VitalReading>>{};
    for (final r in readings) {
      final key = DateFormat.yMMMMd().format(r.recordedAt);
      groups.putIfAbsent(key, () => []).add(r);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: groups.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                ),
                child: Text(
                  e.key,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        letterSpacing: 0.3,
                      ),
                ),
              ),
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < e.value.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.xs),
                      _HistoryRow(r: e.value[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.r});
  final VitalReading r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = r.vital.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => VitalReadingSheet.show(context, reading: r),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: r.risk == RiskLevel.normal
                ? (AppPalette.isDark(context)
                    ? AppColors.darkSurfaceAlt.withOpacity(0.65)
                    : Colors.white.withOpacity(0.28))
                : r.risk.softBg(context).withOpacity(0.35),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: r.risk.color.withOpacity(
                r.risk == RiskLevel.normal ? 0.14 : 0.22,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(r.vital.icon, color: accent, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: r.formatValue(),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                              fontSize: 14,
                            ),
                          ),
                          TextSpan(
                            text: ' ${r.vital.unit}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppPalette.textMuted(context),
                              fontWeight: FontWeight.w500,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat.jm().format(r.recordedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              RiskBadge(risk: r.risk, dense: true),
              const SizedBox(width: 2),
              Icon(
                AppIcons.chevronRight,
                size: 14,
                color: accent.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_floating_button.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/trend_chart.dart';
import 'submit_vital_sheet.dart';
import 'vital_reading_sheet.dart';

enum _Range { d7, d30, d90 }

extension on _Range {
  int get days => switch (this) {
        _Range.d7 => 7,
        _Range.d30 => 30,
        _Range.d90 => 90,
      };
  String get label => switch (this) {
        _Range.d7 => '7 days',
        _Range.d30 => '30 days',
        _Range.d90 => '90 days',
      };
}

String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

class VitalDetailView extends StatefulWidget {
  const VitalDetailView({
    super.key,
    required this.vital,
    this.initialRangeDays = 7,
  });
  final VitalKey vital;
  final int initialRangeDays;

  @override
  State<VitalDetailView> createState() => _VitalDetailViewState();
}

class _VitalDetailViewState extends State<VitalDetailView> {
  late _Range _range;

  @override
  void initState() {
    super.initState();
    _range = _rangeFromDays(widget.initialRangeDays);
  }

  _Range _rangeFromDays(int days) => switch (days) {
        7 => _Range.d7,
        30 => _Range.d30,
        90 => _Range.d90,
        _ => _Range.d7,
      };

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);
    final handheld = tier.isHandheld;

    return PatientScaffold(
      currentRoute: RouteNames.patientVitals,
      detachedNav: true,
      title: widget.vital.label,
      subtitle: 'Trends, stats and history',
      body: AnimatedBuilder(
        animation: Listenable.merge([
          VitalsState.instance,
          NotificationState.instance,
        ]),
        builder: (context, _) {
          final vital = widget.vital;
          final all = VitalsState.instance.forVital(vital);
          final cutoff = DateTime.now().subtract(Duration(days: _range.days));
          final inRange = all
              .where((r) => r.recordedAt.isAfter(cutoff))
              .toList()
            ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
          final latest = VitalsState.instance.latestOf(vital);
          final alert = NotificationState.instance.vitalAlertFor(vital);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: _VitalHero(
                  vital: vital,
                  latest: latest,
                  alert: alert,
                  rangeLabel: _range.label,
                  readingCount: inRange.length,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: _RangeTabs(
                  value: _range,
                  onChanged: (r) => setState(() => _range = r),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: inRange.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: EmptyStateView(
                            icon: AppIcons.trend,
                            title: 'No readings in this range',
                            actionLabel: 'Log a reading',
                            onAction: () => SubmitVitalSheet.show(
                              context,
                              initial: vital,
                            ),
                            compact: true,
                          ),
                        )
                      : TrendChart(
                          readings: inRange,
                          vital: vital,
                          height: handheld ? 200 : 240,
                        ),
                ),
              ),
              if (inRange.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 3,
                  child: _StatsGrid(readings: inRange, vital: vital),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              StaggeredEntry(
                index: 4,
                child: SectionLabel(
                  title: 'Recent readings',
                  icon: AppIcons.records,
                  actionLabel: inRange.isEmpty ? null : 'See all',
                  onAction: inRange.isEmpty
                      ? null
                      : () => Navigator.of(context).pushNamed(
                            RouteNames.patientVitalHistory,
                            arguments: vital,
                          ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 5,
                child: _HistoryList(
                  vital: vital,
                  readings: inRange.take(8).toList(),
                ),
              ),
              SizedBox(height: handheld ? 88 : AppSpacing.huge),
            ],
          );
        },
      ),
      floatingActionButton: handheld
          ? GlassFloatingButton(
              icon: AppIcons.add,
              label: 'Log vital',
              accent: widget.vital.accent,
              onPressed: () =>
                  SubmitVitalSheet.show(context, initial: widget.vital),
            )
          : null,
    );
  }
}

class _VitalHero extends StatelessWidget {
  const _VitalHero({
    required this.vital,
    required this.latest,
    required this.alert,
    required this.rangeLabel,
    required this.readingCount,
  });

  final VitalKey vital;
  final VitalReading? latest;
  final AppNotification? alert;
  final String rangeLabel;
  final int readingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.accent;
    final risk = latest?.risk ?? RiskLevel.unknown;
    final isAlert = alert != null;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: accent.withOpacity(0.25)),
                ),
                child: Icon(vital.icon, color: accent, size: 24),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vital.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
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
              if (latest != null) _statusBadge(risk, theme),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    VitalReadingSheet.show(context, reading: latest!),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: accent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.time, size: 14, color: accent),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Latest ${_relativeTime(latest!.recordedAt)} · ',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppPalette.textMuted(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text: latest!.formatValue(),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          TextSpan(
                            text: ' ${vital.unit}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppPalette.textMuted(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    AppIcons.chevronRight,
                    size: 14,
                    color: accent.withOpacity(0.7),
                  ),
                ],
              ),
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'No readings logged yet — tap Log vital below.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            ),
          if (isAlert) ...[
            const SizedBox(height: AppSpacing.sm),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    VitalReadingSheet.show(context, reading: latest!),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: AppPalette.criticalSoft(context).withOpacity(0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: AppColors.critical.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    AppIcons.alert,
                    size: 14,
                    color: AppColors.critical,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      alert!.title,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.critical,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    AppIcons.chevronRight,
                    size: 14,
                    color: AppColors.critical.withOpacity(0.7),
                  ),
                ],
              ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(RiskLevel risk, ThemeData theme) {
    return RiskBadge(risk: risk, dense: true);
  }
}

class _RangeTabs extends StatelessWidget {
  const _RangeTabs({required this.value, required this.onChanged});
  final _Range value;
  final ValueChanged<_Range> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: _Range.values
            .map(
              (r) => Expanded(
                child: InkWell(
                  onTap: () => onChanged(r),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: r == value
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      r.label,
                      style: TextStyle(
                        color: r == value
                            ? Colors.white
                            : AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.readings, required this.vital});
  final List<VitalReading> readings;
  final VitalKey vital;

  @override
  Widget build(BuildContext context) {
    final values = readings.map((r) => r.value).toList();
    final avg = values.reduce((a, b) => a + b) / values.length;
    final mn = values.reduce((a, b) => a < b ? a : b);
    final mx = values.reduce((a, b) => a > b ? a : b);

    String fmt(double v) =>
        v.toStringAsFixed(vital == VitalKey.temperature ? 1 : 0);

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatCell(
                label: 'Average',
                value: fmt(avg),
                unit: vital.unit,
              ),
              _StatDivider(),
              _StatCell(
                label: 'Lowest',
                value: fmt(mn),
                unit: vital.unit,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Divider(height: 1, color: AppPalette.border(context)),
          ),
          Row(
            children: [
              _StatCell(
                label: 'Highest',
                value: fmt(mx),
                unit: vital.unit,
              ),
              _StatDivider(),
              _StatCell(
                label: 'Readings',
                value: '${readings.length}',
                unit: 'total',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      width: 1,
      color: AppPalette.border(context),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.vital, required this.readings});

  final VitalKey vital;
  final List<VitalReading> readings;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return GlassCard(
        frosted: true,
        child: EmptyStateView(
          icon: vital.icon,
          title: 'No readings yet',
          message: 'Log your first ${vital.shortLabel} reading to see history.',
          actionLabel: 'Log vital',
          onAction: () => SubmitVitalSheet.show(context, initial: vital),
          compact: true,
        ),
      );
    }

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          for (var i = 0; i < readings.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            _HistoryRow(r: readings[i]),
          ],
        ],
      ),
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
                height: 34,
                width: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(r.vital.icon, color: accent, size: 17),
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
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              height: 1.1,
                            ),
                          ),
                          TextSpan(
                            text: ' ${r.vital.unit}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppPalette.textMuted(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat.MMMEd().add_jm().format(r.recordedAt),
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
                size: 16,
                color: accent.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

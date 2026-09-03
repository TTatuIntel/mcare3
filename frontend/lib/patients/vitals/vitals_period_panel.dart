import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/patient_chart_api.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/vital_navigation.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/period_filter_bar.dart';
import '../../shared/widgets/vital_tile.dart';
import 'request_vital_report_sheet.dart';
import 'submit_vital_sheet.dart';

/// Which question the panel under the filter is answering.
enum VitalsLens {
  latest,
  history,
  resolved;

  String get label => switch (this) {
    VitalsLens.latest => 'Latest',
    VitalsLens.history => 'History',
    VitalsLens.resolved => 'Resolved',
  };

  IconData get icon => switch (this) {
    VitalsLens.latest => AppIcons.vitals,
    VitalsLens.history => AppIcons.history,
    VitalsLens.resolved => AppIcons.check,
  };
}

/// The vitals page's time filter and everything that answers to it.
///
/// The row this replaces was three shortcuts — a fixed "past 7 days" jump, a
/// report button and a resolved-alerts link — each leaving for somewhere else.
/// None of them filtered anything, so the readings underneath always showed
/// the same last six regardless of what the patient wanted to look at.
///
/// One window governs the whole section instead: pick it once, in a control
/// that offers presets, calendar spans and two dates off a month grid, and the
/// readings, the history and the closed alerts underneath all answer for that
/// window. Requesting a report from here carries the same window into the
/// request, so what the patient is looking at is what they ask to be sent.
class VitalsPeriodSection extends StatefulWidget {
  const VitalsPeriodSection({
    super.key,
    required this.period,
    required this.onPeriodChanged,
    required this.tracked,
  });

  final ChartPeriod period;
  final ValueChanged<ChartPeriod> onPeriodChanged;
  final List<VitalKey> tracked;

  @override
  State<VitalsPeriodSection> createState() => _VitalsPeriodSectionState();
}

class _VitalsPeriodSectionState extends State<VitalsPeriodSection> {
  VitalsLens _lens = VitalsLens.latest;

  @override
  Widget build(BuildContext context) {
    final window = widget.period.resolve();
    final readings = VitalsState.instance.readingsBetween(
      window.from,
      window.to,
      vitals: widget.tracked,
    );
    final resolved = NotificationState.instance.resolvedVitalAlertsBetween(
      window.from,
      window.to,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeriodFilterBar(
          period: widget.period,
          onChanged: widget.onPeriodChanged,
          title: 'Readings period',
          subtitle: 'Everything below answers for the window you choose.',
        ),
        const SizedBox(height: AppSpacing.sm),
        _LensBar(
          lens: _lens,
          onChanged: (lens) => setState(() => _lens = lens),
          readingCount: readings.length,
          resolvedCount: resolved.length,
          onRequestReport: () => RequestVitalReportSheet.show(
            context,
            initialPeriod: widget.period,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        switch (_lens) {
          VitalsLens.latest => _LatestPanel(
            readings: readings,
            period: widget.period,
          ),
          VitalsLens.history => _HistoryPanel(
            readings: readings,
            period: widget.period,
          ),
          VitalsLens.resolved => _ResolvedPanel(
            alerts: resolved,
            period: widget.period,
          ),
        },
      ],
    );
  }
}

/// Three lenses on the same window, plus the one thing that leaves it. Sits on
/// the page background rather than in a card: it is a control, not content.
class _LensBar extends StatelessWidget {
  const _LensBar({
    required this.lens,
    required this.onChanged,
    required this.readingCount,
    required this.resolvedCount,
    required this.onRequestReport,
  });

  final VitalsLens lens;
  final ValueChanged<VitalsLens> onChanged;
  final int readingCount;
  final int resolvedCount;
  final VoidCallback onRequestReport;

  int? _countFor(VitalsLens value) => switch (value) {
    VitalsLens.latest => null,
    VitalsLens.history => readingCount,
    VitalsLens.resolved => resolvedCount,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final value in VitalsLens.values) ...[
          Expanded(
            child: _LensButton(
              lens: value,
              selected: value == lens,
              count: _countFor(value),
              onTap: () => onChanged(value),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        _ReportButton(onTap: onRequestReport),
      ],
    );
  }
}

class _LensButton extends StatelessWidget {
  const _LensButton({
    required this.lens,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final VitalsLens lens;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final ink = selected ? accent : AppPalette.textMuted(context);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.35)
                    : AppPalette.border(context),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(lens.icon, size: 14, color: ink),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    lens.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: 'Request a report for this period',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              color: accent.withValues(alpha: 0.08),
            ),
            child: Icon(AppIcons.report, size: 15, color: accent),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Latest — the newest reading per tracked vital, inside the window
// ---------------------------------------------------------------------------

class _LatestPanel extends StatelessWidget {
  const _LatestPanel({required this.readings, required this.period});

  final List<VitalReading> readings;
  final ChartPeriod period;

  /// One row per vital: the most recent reading of each inside the window.
  /// A list of the last six readings overall buries a vital that was measured
  /// once behind one that was measured every hour.
  List<VitalReading> get _newestPerVital {
    final seen = <VitalKey, VitalReading>{};
    for (final reading in readings) {
      seen.putIfAbsent(reading.vital, () => reading);
    }
    final list = seen.values.toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = _newestPerVital;

    if (latest.isEmpty) {
      return _EmptyPanel(
        title: 'No readings in this period',
        message:
            'Nothing was recorded between ${period.rangeText}. '
            'Widen the window, or log a reading now.',
        actionLabel: 'Log vital',
        onAction: () => SubmitVitalSheet.show(context),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            dotColor: AppColors.success,
            text:
                'Newest of each vital · ${latest.length} of '
                '${readings.length} reading${readings.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < latest.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            VitalTile(
              vital: latest[i].vital,
              reading: latest[i],
              onTap: () => openVitalDetail(context, latest[i].vital),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Showing ${period.label.toLowerCase()}.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// History — every reading in the window, grouped by the day it was taken
// ---------------------------------------------------------------------------

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.readings, required this.period});

  final List<VitalReading> readings;
  final ChartPeriod period;

  /// Readings bucketed by day, newest day first. Days with nothing recorded
  /// are simply absent — a run of empty rows says nothing a date range does
  /// not already say.
  List<MapEntry<DateTime, List<VitalReading>>> get _byDay {
    final buckets = <DateTime, List<VitalReading>>{};
    for (final reading in readings) {
      final day = DateTime(
        reading.recordedAt.year,
        reading.recordedAt.month,
        reading.recordedAt.day,
      );
      buckets.putIfAbsent(day, () => []).add(reading);
    }
    final entries = buckets.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return _EmptyPanel(
        title: 'Nothing recorded in this period',
        message:
            'No readings between ${period.rangeText}. '
            'Step the window back, or log a reading now.',
        actionLabel: 'Log vital',
        onAction: () => SubmitVitalSheet.show(context),
      );
    }

    final days = _byDay;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            dotColor: Theme.of(context).colorScheme.primary,
            text:
                '${readings.length} reading${readings.length == 1 ? '' : 's'} '
                'across ${days.length} day${days.length == 1 ? '' : 's'}',
          ),
          for (final day in days) ...[
            const SizedBox(height: AppSpacing.sm),
            _DayHeader(day: day.key, count: day.value.length),
            for (final reading in day.value) ...[
              const SizedBox(height: AppSpacing.xs),
              VitalTile(
                vital: reading.vital,
                reading: reading,
                onTap: () => openVitalDetail(context, reading.vital),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.count});

  final DateTime day;
  final int count;

  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Yesterday',
      _ => DateFormat('EEE, MMM d').format(day),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          _label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontWeight: FontWeight.w800,
            fontSize: 10,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Container(height: 1, color: AppPalette.border(context)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$count',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Resolved — alerts the care team closed, and what they said about them
// ---------------------------------------------------------------------------

class _ResolvedPanel extends StatelessWidget {
  const _ResolvedPanel({required this.alerts, required this.period});

  final List<AppNotification> alerts;
  final ChartPeriod period;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return _EmptyPanel(
        title: 'No alerts closed in this period',
        message:
            'When your care team reviews a reading that raised an alert, '
            'what they decided appears here for ${period.rangeText}.',
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(
            dotColor: AppColors.success,
            text:
                '${alerts.length} alert${alerts.length == 1 ? '' : 's'} '
                'reviewed and closed',
          ),
          for (var i = 0; i < alerts.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1, color: AppPalette.border(context)),
              )
            else
              const SizedBox(height: AppSpacing.sm),
            _ResolvedAlertRow(alert: alerts[i]),
          ],
        ],
      ),
    );
  }
}

class _ResolvedAlertRow extends StatelessWidget {
  const _ResolvedAlertRow({required this.alert});

  final AppNotification alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vital = alert.linkedVital;
    final closedAt = alert.resolvedAt ?? alert.createdAt;
    final note = alert.resolutionNote;
    final action = alert.resolutionAction;

    return InkWell(
      onTap: vital == null ? null : () => openVitalDetail(context, vital),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 30,
                  width: 30,
                  decoration: BoxDecoration(
                    color: AppPalette.successSoft(context),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(
                    vital?.icon ?? AppIcons.check,
                    size: 15,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vital?.label ?? alert.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Closed ${DateFormat.yMMMd().add_jm().format(closedAt)}'
                        '${alert.resolvedBy == null ? '' : ' · ${alert.resolvedBy}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (vital != null)
                  Icon(
                    AppIcons.chevronRight,
                    size: 16,
                    color: AppPalette.textMuted(context),
                  ),
              ],
            ),

            // The reading that raised it, in the words the alert used.
            if (alert.body.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Text(
                  alert.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    height: 1.35,
                  ),
                ),
              ),
            ],

            if (action != null || (note ?? '').isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(left: 38),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (action != null)
                        Row(
                          children: [
                            const Icon(
                              AppIcons.acknowledge,
                              size: 12,
                              color: AppColors.success,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                action,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if ((note ?? '').isNotEmpty) ...[
                        if (action != null) const SizedBox(height: 4),
                        Text(
                          note!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared panel furniture
// ---------------------------------------------------------------------------

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.dotColor, required this.text});

  final Color dotColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 8,
          width: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      child: EmptyStateView(
        icon: AppIcons.vitals,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: onAction,
        compact: true,
      ),
    );
  }
}

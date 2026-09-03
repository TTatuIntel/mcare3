import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/patient_chart_api.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/models/vital_statistics.dart';
import '../../shared/navigation/vital_navigation.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/period_filter_bar.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/trend_chart.dart';
import 'request_vital_report_sheet.dart';
import 'submit_vital_sheet.dart';

List<VitalReading> _readingsInPeriod(
  Iterable<VitalReading> readings,
  ChartPeriod period,
) {
  final window = period.resolve();
  return readings
      .where(
        (reading) =>
            !reading.recordedAt.isBefore(window.from) &&
            !reading.recordedAt.isAfter(window.to),
      )
      .toList();
}

/// One dynamic, tappable insight rail — flat on the page, no card.
///
/// The band used to be a single static row that mostly said "there is a chart
/// behind this". The same strip of screen now cycles the things a patient
/// actually opens it to learn — what needs attention, what is due to be
/// recorded, the last reading, an estimated health score, the period
/// statistics and the history — and every page lands on the screen that
/// answers it. It is ordered by what matters most right now, and it moves
/// only when the reader swipes or taps a dot.
class PatientVitalInsightsLauncher extends StatefulWidget {
  const PatientVitalInsightsLauncher({
    super.key,
    this.title = 'Statistics & charts',
    this.period = ChartPeriod.threeWeeks,
  });

  /// Label of the always-present statistics entry under the rail.
  final String title;

  /// Window the summary statistics are read over.
  final ChartPeriod period;

  @override
  State<PatientVitalInsightsLauncher> createState() =>
      _PatientVitalInsightsLauncherState();
}

class _PatientVitalInsightsLauncherState
    extends State<PatientVitalInsightsLauncher> {
  static const double _pageHeight = 84;

  /// A tracked vital with nothing logged since this long ago is "due".
  static const Duration _dueAfter = Duration(hours: 20);

  final _pageController = PageController();
  int _pageIndex = 0;
  int _pageCount = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- paging

  /// The rail never advances on its own — a page a reader is halfway through
  /// must not slide away under them. Paging is a swipe or a dot, and the only
  /// automatic move is stepping back when the insight list gets shorter.
  void _syncPageCount(int pageCount) {
    _pageCount = pageCount;
    if (pageCount > 0 && _pageIndex >= pageCount) {
      setState(() => _pageIndex = pageCount - 1);
      if (_pageController.hasClients) _pageController.jumpToPage(pageCount - 1);
    }
  }

  void _goToPage(int page) {
    if (!_pageController.hasClients || _pageCount <= 1) return;
    _pageController.animateToPage(
      page.clamp(0, _pageCount - 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOut,
    );
  }

  // -------------------------------------------------------------- insights

  /// Tracked vitals with nothing logged inside [_dueAfter], doctor-assigned
  /// ones first — those are the readings someone is waiting on.
  List<VitalKey> _dueVitals(VitalsState state, List<VitalKey> tracked) {
    final now = DateTime.now();
    final due = tracked.where((vital) {
      final reading = state.latestOf(vital);
      return reading == null || now.difference(reading.recordedAt) >= _dueAfter;
    }).toList();
    due.sort((a, b) {
      final assigned =
          (state.isAssigned(b) ? 1 : 0) - (state.isAssigned(a) ? 1 : 0);
      if (assigned != 0) return assigned;
      return a.index.compareTo(b.index);
    });
    return due;
  }

  /// The one vital worth interrupting for: an open alert first, then the
  /// worst unresolved risk on a latest reading.
  VitalKey? _attentionVital(VitalsState state, List<VitalKey> tracked) {
    for (final vital in tracked) {
      if (NotificationState.instance.vitalAlertFor(vital) != null) return vital;
    }
    VitalKey? warning;
    for (final vital in tracked) {
      switch (state.latestOf(vital)?.risk) {
        case RiskLevel.critical:
          return vital;
        case RiskLevel.warning:
          warning ??= vital;
        default:
          break;
      }
    }
    return warning;
  }

  VitalReading? _latestReading(VitalsState state) {
    VitalReading? latest;
    for (final reading in state.all) {
      if (latest == null || reading.recordedAt.isAfter(latest.recordedAt)) {
        latest = reading;
      }
    }
    return latest;
  }

  List<_VitalInsight> _insights(BuildContext context) {
    final state = VitalsState.instance;
    final period = widget.period;
    final tracked = state.tracked.toList();
    final periodReadings = _readingsInPeriod(state.all, period);
    final stats = VitalStatistics.from(periodReadings);
    final latest = _latestReading(state);
    final insights = <_VitalInsight>[];

    final attention = _attentionVital(state, tracked);
    if (attention != null) {
      final reading = state.latestOf(attention);
      final risk = reading?.risk ?? RiskLevel.warning;
      insights.add(
        _VitalInsight(
          id: 'attention',
          icon: AppIcons.alert,
          accent: risk == RiskLevel.critical
              ? AppColors.critical
              : AppColors.warning,
          title: 'Needs attention · ${attention.shortLabel}',
          detail: reading == null
              ? 'Your care team flagged this vital. Open it to see why.'
              : '${reading.formatValue()} ${attention.unit} · '
                    'recorded ${_insightAgo(reading.recordedAt)}',
          badge: risk.label,
          onTap: () => openVitalDetail(context, attention),
        ),
      );
    }

    final due = _dueVitals(state, tracked);
    if (due.isNotEmpty) {
      final names = due.take(3).map((vital) => vital.shortLabel).join(', ');
      insights.add(
        _VitalInsight(
          id: 'due',
          icon: AppIcons.time,
          accent: AppColors.brandIndigo,
          title: due.length == 1
              ? 'Time to record ${due.first.shortLabel}'
              : '${due.length} vitals due',
          detail: latest == null
              ? 'Nothing logged yet · $names'
              : 'Nothing new in a day · $names',
          badge: 'Log now',
          onTap: () => SubmitVitalSheet.show(context, initial: due.first),
        ),
      );
    }

    if (latest != null) {
      insights.add(
        _VitalInsight(
          id: 'latest',
          icon: latest.vital.icon,
          accent: latest.vital.accent,
          title: latest.vital.label,
          detail:
              '${latest.formatValue()} ${latest.vital.unit} · '
              '${latest.risk.label} · ${_insightAgo(latest.recordedAt)}',
          badge: 'Latest',
          onTap: () => openVitalDetail(context, latest.vital),
        ),
      );
    }

    final estimate = _VitalHealthEstimate.of(state, periodReadings, tracked);
    insights.add(
      _VitalInsight(
        id: 'estimate',
        icon: AppIcons.analytics,
        accent: estimate.color,
        title: estimate.score == null
            ? 'Health estimate'
            : 'Health estimate ${estimate.score}%',
        detail: estimate.detail,
        badge: estimate.score == null ? null : estimate.label,
        progress: estimate.score == null ? null : estimate.score! / 100,
        onTap: () =>
            PatientVitalInsightsSheet.show(context, initialPeriod: period),
      ),
    );

    if (periodReadings.isNotEmpty) {
      final measured = periodReadings.map((r) => r.vital).toSet().length;
      insights.add(
        _VitalInsight(
          id: 'statistics',
          icon: AppIcons.trend,
          accent: AppColors.brandIndigo,
          title: 'Statistics · ${period.shortLabel}',
          detail:
              '${stats.count} reading${stats.count == 1 ? '' : 's'} · '
              '${stats.trend.label} · '
              '$measured vital${measured == 1 ? '' : 's'} measured',
          badge: '${stats.inRangePercent ?? 0}% in range',
          onTap: () =>
              PatientVitalInsightsSheet.show(context, initialPeriod: period),
        ),
      );
    }

    insights.add(
      _VitalInsight(
        id: 'history',
        icon: AppIcons.history,
        accent: AppColors.brandIndigo,
        title: 'Vital history',
        detail: 'Every reading you have logged, newest first',
        onTap: () => Navigator.of(context).pushNamed(
          RouteNames.patientVitalHistory,
          arguments:
              latest?.vital ??
              (tracked.isEmpty ? VitalKey.heartRate : tracked.first),
        ),
      ),
    );

    return insights;
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        VitalsState.instance,
        NotificationState.instance,
      ]),
      builder: (context, _) {
        final insights = _insights(context);
        final stats = VitalStatistics.from(
          _readingsInPeriod(VitalsState.instance.all, widget.period),
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncPageCount(insights.length);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              title: 'Vitals insights',
              icon: AppIcons.trend,
              trailing: stats.count == 0
                  ? 'No readings yet'
                  : '${stats.count} in ${widget.period.shortLabel}',
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: AppPalette.border(context)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: _pageHeight,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: insights.length,
                      onPageChanged: (index) =>
                          setState(() => _pageIndex = index),
                      itemBuilder: (context, index) =>
                          _InsightPage(insight: insights[index]),
                    ),
                  ),
                  _InsightFooter(
                    count: insights.length,
                    index: _pageIndex.clamp(0, insights.length - 1),
                    title: widget.title,
                    onDotTap: _goToPage,
                    onOpen: () => PatientVitalInsightsSheet.show(
                      context,
                      initialPeriod: widget.period,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One page of the rail: an icon (or score ring), a headline, a line of
/// detail, an optional pill and the tap that opens the screen behind it.
class _VitalInsight {
  const _VitalInsight({
    required this.id,
    required this.icon,
    required this.accent,
    required this.title,
    required this.detail,
    required this.onTap,
    this.badge,
    this.progress,
  });

  final String id;
  final IconData icon;
  final Color accent;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final String? badge;

  /// 0..1 — draws the leading circle as a score ring instead of a plain icon.
  final double? progress;
}

class _InsightPage extends StatelessWidget {
  const _InsightPage({required this.insight});

  final _VitalInsight insight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${insight.title}. ${insight.detail}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('vital-insight-${insight.id}'),
          onTap: insight.onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                _InsightLeading(
                  icon: insight.icon,
                  accent: insight.accent,
                  progress: insight.progress,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        insight.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        insight.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (insight.badge != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  _InsightBadge(label: insight.badge!, accent: insight.accent),
                ],
                Icon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: AppPalette.textMuted(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InsightLeading extends StatelessWidget {
  const _InsightLeading({
    required this.icon,
    required this.accent,
    this.progress,
  });

  final IconData icon;
  final Color accent;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    if (progress != null) {
      return SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                value: progress!.clamp(0, 1),
                strokeWidth: 3.5,
                backgroundColor: accent.withValues(alpha: 0.16),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            Text(
              '${(progress! * 100).round()}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 19, color: accent),
    );
  }
}

class _InsightBadge extends StatelessWidget {
  const _InsightBadge({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Page dots on the left, the permanent way into the full charts on the right.
class _InsightFooter extends StatelessWidget {
  const _InsightFooter({
    required this.count,
    required this.index,
    required this.title,
    required this.onDotTap,
    required this.onOpen,
  });

  final int count;
  final int index;
  final String title;
  final ValueChanged<int> onDotTap;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (count > 1)
            for (var i = 0; i < count; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onDotTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 6,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: i == index ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == index
                          ? AppColors.brandIndigo
                          : AppPalette.borderStrong(context),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                    ),
                  ),
                ),
              ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('open-vital-insights'),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.brandIndigo,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(
                      AppIcons.chevronRight,
                      size: 16,
                      color: AppColors.brandIndigo,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain-language score for the rail — deliberately an *estimate*, and
/// labelled as one. It reads only what the app already knows: how much of the
/// period was in range, how much of the tracked set is being kept up to date,
/// and whether anything is currently flagged.
class _VitalHealthEstimate {
  const _VitalHealthEstimate({
    required this.score,
    required this.label,
    required this.detail,
    required this.color,
  });

  final int? score;
  final String label;
  final String detail;
  final Color color;

  static _VitalHealthEstimate of(
    VitalsState state,
    List<VitalReading> periodReadings,
    List<VitalKey> tracked,
  ) {
    if (periodReadings.isEmpty) {
      return const _VitalHealthEstimate(
        score: null,
        label: 'No data',
        detail: 'Log a few readings and an estimate appears here',
        color: AppColors.textMutedAA,
      );
    }

    final stats = VitalStatistics.from(periodReadings);
    final inRange = (stats.inRangePercent ?? 0).toDouble();

    final now = DateTime.now();
    var current = 0;
    for (final vital in tracked) {
      final reading = state.latestOf(vital);
      if (reading != null &&
          now.difference(reading.recordedAt) <= const Duration(days: 3)) {
        current++;
      }
    }
    final upkeep = tracked.isEmpty ? 1.0 : current / tracked.length;

    var score = inRange * 0.65 + upkeep * 100 * 0.35;
    for (final vital in tracked) {
      if (NotificationState.instance.vitalAlertFor(vital) != null) score -= 8;
      switch (state.latestOf(vital)?.risk) {
        case RiskLevel.critical:
          score -= 6;
        case RiskLevel.warning:
          score -= 3;
        default:
          break;
      }
    }

    final value = score.clamp(0, 100).round();
    final (label, color) = switch (value) {
      >= 85 => ('Excellent', AppColors.success),
      >= 70 => ('On track', AppColors.success),
      >= 55 => ('Fair', AppColors.warning),
      _ => ('Needs care', AppColors.critical),
    };

    return _VitalHealthEstimate(
      score: value,
      label: label,
      detail:
          '${inRange.round()}% in range · '
          '${(upkeep * 100).round()}% of tracked vitals up to date',
      color: color,
    );
  }
}

String _insightAgo(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.MMMd().format(at);
}

class PatientVitalInsightsSheet {
  PatientVitalInsightsSheet._();

  static Future<void> show(
    BuildContext context, {
    VitalKey? initialVital,
    ChartPeriod initialPeriod = ChartPeriod.threeWeeks,
  }) {
    return GlassSheet.show(
      context,
      title: 'Vital statistics & charts',
      subtitle: 'Explore trends without crowding your dashboard',
      maxWidth: 760,
      child: _PatientVitalInsightsBody(
        initialVital: initialVital,
        initialPeriod: initialPeriod,
      ),
    );
  }
}

class _PatientVitalInsightsBody extends StatefulWidget {
  const _PatientVitalInsightsBody({
    required this.initialVital,
    required this.initialPeriod,
  });

  final VitalKey? initialVital;
  final ChartPeriod initialPeriod;

  @override
  State<_PatientVitalInsightsBody> createState() =>
      _PatientVitalInsightsBodyState();
}

class _PatientVitalInsightsBodyState extends State<_PatientVitalInsightsBody> {
  late ChartPeriod _period = widget.initialPeriod;
  VitalKey? _selectedVital;

  List<VitalKey> get _availableVitals {
    final state = VitalsState.instance;
    final keys = <VitalKey>{...state.tracked, ...state.all.map((r) => r.vital)};
    return keys.toList()..sort((a, b) {
      final aHasData = state.forVital(a).isNotEmpty;
      final bHasData = state.forVital(b).isNotEmpty;
      if (aHasData != bHasData) return aHasData ? -1 : 1;
      return a.index.compareTo(b.index);
    });
  }

  VitalKey? _effectiveVital(List<VitalKey> available) {
    if (_selectedVital != null && available.contains(_selectedVital)) {
      return _selectedVital;
    }
    if (widget.initialVital != null &&
        available.contains(widget.initialVital)) {
      return widget.initialVital;
    }
    return available.isEmpty ? null : available.first;
  }

  String _format(VitalKey vital, double? value) {
    if (value == null) return '—';
    final decimals = vital == VitalKey.temperature || vital == VitalKey.weight;
    return value.toStringAsFixed(decimals ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VitalsState.instance,
      builder: (context, _) {
        final available = _availableVitals;
        final vital = _effectiveVital(available);
        if (vital == null) {
          return EmptyStateView(
            icon: AppIcons.trend,
            title: 'No vitals to chart',
            message: 'Log a vital first, then its statistics will appear here.',
            actionLabel: 'Log vital',
            onAction: () => SubmitVitalSheet.show(context),
            compact: true,
          );
        }

        final readings = _readingsInPeriod(
          VitalsState.instance.forVital(vital),
          _period,
        );
        final stats = VitalStatistics.from(readings);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PeriodFilterBar(
              period: _period,
              title: 'Chart period',
              subtitle: 'The chart and report statistics use this same range.',
              accent: vital.accent,
              onChanged: (period) => setState(() => _period = period),
            ),
            const SizedBox(height: AppSpacing.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final option in available)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: FilterChip(
                        avatar: Icon(
                          option.icon,
                          size: 15,
                          color: option.accent,
                        ),
                        label: Text(option.shortLabel),
                        selected: option == vital,
                        onSelected: (_) =>
                            setState(() => _selectedVital = option),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (readings.isEmpty)
              EmptyStateView(
                icon: vital.icon,
                title: 'No ${vital.label.toLowerCase()} readings',
                message: 'Try another period or add a new reading.',
                actionLabel: 'Log ${vital.shortLabel}',
                onAction: () => SubmitVitalSheet.show(context, initial: vital),
                compact: true,
              )
            else ...[
              _InsightMetrics(
                average: _format(vital, stats.average),
                lowest: _format(vital, stats.lowest),
                highest: _format(vital, stats.highest),
                inRange: '${stats.inRangePercent ?? 0}%',
                unit: vital.unit,
              ),
              const SizedBox(height: AppSpacing.md),
              TrendChart(readings: readings, vital: vital, height: 210),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${stats.count} reading${stats.count == 1 ? '' : 's'} · '
                '${stats.trend.label} trend · ${_period.rangeText}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Use these dates in a report',
              icon: AppIcons.report,
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () => RequestVitalReportSheet.show(
                context,
                initialPeriod: _period,
                initialVitals: {vital},
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InsightMetrics extends StatelessWidget {
  const _InsightMetrics({
    required this.average,
    required this.lowest,
    required this.highest,
    required this.inRange,
    required this.unit,
  });

  final String average;
  final String lowest;
  final String highest;
  final String inRange;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _InsightMetric(label: 'Average', value: average, unit: unit),
          ),
          const VerticalDivider(width: AppSpacing.sm),
          Expanded(
            child: _InsightMetric(label: 'Lowest', value: lowest, unit: unit),
          ),
          const VerticalDivider(width: AppSpacing.sm),
          Expanded(
            child: _InsightMetric(label: 'Highest', value: highest, unit: unit),
          ),
          const VerticalDivider(width: AppSpacing.sm),
          Expanded(
            child: _InsightMetric(label: 'In range', value: inRange),
          ),
        ],
      ),
    );
  }
}

class _InsightMetric extends StatelessWidget {
  const _InsightMetric({required this.label, required this.value, this.unit});

  final String label;
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            unit == null ? value : '$value $unit',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppPalette.ink(context),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/api/patient_chart_api.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../app_icons.dart';

/// The pieces the patient chart is built from.
///
/// Every section of the chart is the same shape — a header that answers the
/// question on its own, and a body that is only opened when the answer is not
/// enough. A responder mid-emergency should be able to read the whole chart
/// without opening anything; a clinician reviewing a month should be able to
/// open everything.

/// Colour for a row's tone word. Kept in one place so 'Active' means the same
/// green in medications as in the care team.
Color chartTone(BuildContext context, String? tone) => switch (tone) {
  'critical' => AppColors.critical,
  'warning' => AppColors.warning,
  'success' => AppColors.success,
  'info' => AppColors.info,
  _ => AppPalette.textMuted(context),
};

/// A collapsible section of the chart.
///
/// Collapsed it still carries the count and a one-line summary, because a
/// section that hides its own answer forces every reader to open all of them.
class ChartSection extends StatefulWidget {
  const ChartSection({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    required this.child,
    this.count,
    this.accent,
    this.initiallyExpanded = false,
    this.trailingAction,
  });

  final String title;
  final IconData icon;

  /// The one line that has to be true whether or not anyone expands this.
  final String summary;
  final Widget child;
  final int? count;
  final Color? accent;
  final bool initiallyExpanded;
  final Widget? trailingAction;

  @override
  State<ChartSection> createState() => ChartSectionState();
}

class ChartSectionState extends State<ChartSection> {
  late bool _open = widget.initiallyExpanded;

  /// Opened from outside — the summary strip at the top of the chart jumps
  /// here, and a section that stayed shut would be a jump to nothing.
  void open() {
    if (_open || !mounted) return;
    setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accent ?? theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.surfaceAlt(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: _open
                ? accent.withValues(alpha: 0.32)
                : AppPalette.border(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Container(
                        height: 32,
                        width: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusSm,
                          ),
                        ),
                        child: Icon(widget.icon, size: 16, color: accent),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.title,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (widget.count != null) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusPill,
                                      ),
                                    ),
                                    child: Text(
                                      '${widget.count}',
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              widget.summary,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppPalette.textMuted(context),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _open ? AppIcons.expandLess : AppIcons.expandMore,
                        size: 20,
                        color: AppPalette.textMuted(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState: _open
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(color: AppPalette.border(context), height: 1),
                    const SizedBox(height: AppSpacing.sm),
                    widget.child,
                    if (widget.trailingAction != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      widget.trailingAction!,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One counted fact of the period, on one line.
///
/// This was a two-column grid of boxed tiles — six of them, three rows deep,
/// each stacking an all-caps label over a number over a caption. Half a phone
/// screen to carry six small integers, before the chart itself started. The
/// count now sits against its own icon and the label is the short word for
/// the thing, so the whole set fits in two wrapped lines.
///
/// Tapping one opens the section it counts: the strip is the chart's index,
/// not decoration. [flag] carries the one thing that would otherwise be lost
/// with the caption — a critical alert, an open SOS, missed doses.
class ChartStatChip extends StatelessWidget {
  const ChartStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.flag,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  /// Set when the count needs qualifying — '2 critical', '1 open'. Shown as a
  /// dot on the chip and spelled out in the tooltip.
  final String? flag;

  /// The full sentence the chip is a shorthand for.
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flagged = flag != null;

    final chip = Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 11, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: accent.withValues(alpha: flagged ? 0.45 : 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 5),
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppPalette.ink(context),
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1.0,
            ),
          ),
          if (flagged) ...[
            const SizedBox(width: 5),
            Container(
              height: 6,
              width: 6,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: tooltip ?? '$value $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          onTap: onTap,
          child: chip,
        ),
      ),
    );
  }
}

/// Circular gauge with the number inside the ring.
class ChartScoreRing extends StatelessWidget {
  const ChartScoreRing({
    super.key,
    required this.value,
    required this.color,
    this.caption = 'of 100',
    this.size = 52,
  });

  final int value;
  final Color color;
  final String caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              strokeWidth: 5,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.31,
                  height: 1.0,
                ),
              ),
              Text(
                caption,
                style: TextStyle(
                  color: color.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.135,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One vital over the period: where it ended, how it moved, how much of the
/// window sat in range, and the line itself.
class ChartVitalTile extends StatelessWidget {
  const ChartVitalTile({super.key, required this.vital});

  final ChartVital vital;

  Color _rangeColor(int? pct) {
    if (pct == null) return AppColors.info;
    if (pct >= 85) return AppColors.success;
    if (pct >= 60) return AppColors.warning;
    return AppColors.critical;
  }

  IconData get _trendIcon => switch (vital.trend) {
    'up' => AppIcons.trendUp,
    'down' => AppIcons.trendDown,
    _ => AppIcons.trend,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.key.accent;
    final points = vital.points;
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppPalette.surface(context),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppPalette.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(vital.key.icon, size: 15, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    vital.key.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (vital.inRangePct != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _rangeColor(
                        vital.inRangePct,
                      ).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                    ),
                    child: Text(
                      '${vital.inRangePct}% in range',
                      style: TextStyle(
                        color: _rangeColor(vital.inRangePct),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // The reading and when it was taken, on one line that cannot
            // overflow: the server's display value already carries the unit
            // ('172/108 mmHg'), so printing key.unit after it both repeated
            // the unit and pushed the timestamp off a narrow phone.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  flex: 3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      vital.latestValue ?? '—',
                      maxLines: 1,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(_trendIcon, size: 14, color: AppPalette.textMuted(context)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: Text(
                    vital.latestAt == null
                        ? '${vital.count} reading${vital.count == 1 ? '' : 's'}'
                        : DateFormat.MMMd().add_jm().format(vital.latestAt!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ),
              ],
            ),
            if (spots.length >= 2) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 68,
                child: LineChart(
                  LineChartData(
                    minY:
                        spots.map((p) => p.y).reduce((a, b) => a < b ? a : b) *
                        0.94,
                    maxY:
                        spots.map((p) => p.y).reduce((a, b) => a > b ? a : b) *
                        1.06,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: const FlTitlesData(show: false),
                    lineTouchData: const LineTouchData(enabled: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        color: accent,
                        barWidth: 2,
                        dotData: FlDotData(
                          show: spots.length <= 24,
                          // Out-of-range readings are the point of the line —
                          // colouring them by risk is what stops a spike
                          // reading as ordinary variation.
                          getDotPainter: (spot, pct, bar, i) =>
                              FlDotCirclePainter(
                                radius: 2.6,
                                color: i < points.length
                                    ? points[i].risk.color
                                    : accent,
                                strokeWidth: 0,
                                strokeColor: Colors.transparent,
                              ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: accent.withValues(alpha: 0.10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else if (vital.count == 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'No readings in this period.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One row of a list section — a medication, an appointment, an alert.
class ChartEntryTile extends StatelessWidget {
  const ChartEntryTile({super.key, required this.entry, this.dateFormat});

  final ChartEntry entry;
  final DateFormat? dateFormat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = chartTone(context, entry.tone);
    final at = entry.at;
    final detail = entry.detail?.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(top: 2, right: AppSpacing.sm),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (entry.trailing != null)
                      Text(
                        entry.trailing!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: tone,
                          fontWeight: FontWeight.w800,
                          fontSize: 9.5,
                        ),
                      ),
                  ],
                ),
                if (entry.subtitle.trim().isNotEmpty)
                  Text(
                    entry.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                if (detail != null && detail.isNotEmpty)
                  Text(
                    detail,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      height: 1.35,
                    ),
                  ),
                if (at != null)
                  Text(
                    (dateFormat ?? DateFormat.yMMMd().add_jm()).format(at),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 9.5,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What a section says when the period holds nothing of its kind. Never
/// "no data" — the reader needs to know the period was searched.
class ChartEmpty extends StatelessWidget {
  const ChartEmpty(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: AppPalette.textMuted(context)),
  );
}

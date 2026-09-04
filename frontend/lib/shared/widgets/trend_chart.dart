import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/vital.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Single chart wrapper for vital trends.
class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.readings,
    required this.vital,
    this.height = 220,
    this.showSecondary = true,
  });

  final List<VitalReading> readings;
  final VitalKey vital;
  final double height;
  final bool showSecondary;

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No readings yet',
            style: TextStyle(color: AppPalette.textMuted(context)),
          ),
        ),
      );
    }

    final sorted = [...readings]
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final accent = vital.accent;
    final range = VitalRanges.defaults[vital]!;

    final primarySpots = <FlSpot>[];
    final secondarySpots = <FlSpot>[];
    for (var i = 0; i < sorted.length; i++) {
      primarySpots.add(FlSpot(i.toDouble(), sorted[i].value));
      if (sorted[i].secondaryValue != null) {
        secondarySpots.add(FlSpot(i.toDouble(), sorted[i].secondaryValue!));
      }
    }

    final allValues = [
      ...sorted.map((r) => r.value),
      ...sorted
          .where((r) => r.secondaryValue != null)
          .map((r) => r.secondaryValue!),
    ];
    final minY = (allValues.reduce((a, b) => a < b ? a : b) - 5)
        .clamp(0, double.infinity)
        .toDouble();
    final maxY = allValues.reduce((a, b) => a > b ? a : b) + 5;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          minX: 0,
          maxX: (sorted.length - 1).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: ((maxY - minY) / 4).clamp(1, double.infinity),
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppPalette.border(context),
              strokeWidth: 1,
              dashArray: const [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: ((maxY - minY) / 4).clamp(1, double.infinity),
                getTitlesWidget: (v, _) => Text(
                  v.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 10,
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (sorted.length / 4).clamp(1, double.infinity),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= sorted.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat.Md().format(sorted[i].recordedAt),
                      style: TextStyle(
                        fontSize: 10,
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: range.normalMax,
                color: AppColors.success.withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
              HorizontalLine(
                y: range.normalMin,
                color: AppColors.success.withValues(alpha: 0.5),
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: primarySpots,
              isCurved: true,
              curveSmoothness: 0.28,
              color: accent,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, pct, bar, idx) {
                  final reading = sorted[spot.x.toInt()];
                  return FlDotCirclePainter(
                    radius: 3.5,
                    color: reading.risk.color,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    accent.withValues(alpha: 0.22),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            if (showSecondary && secondarySpots.isNotEmpty)
              LineChartBarData(
                spots: secondarySpots,
                isCurved: true,
                curveSmoothness: 0.28,
                color: accent.withValues(alpha: 0.55),
                barWidth: 2,
                dashArray: [6, 4],
                dotData: const FlDotData(show: false),
              ),
          ],
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.brandInk,
              tooltipRoundedRadius: AppSpacing.radiusSm,
              getTooltipItems: (spots) => spots.map((s) {
                final reading = sorted[s.x.toInt()];
                return LineTooltipItem(
                  '${reading.formatValue()} ${vital.unit}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  children: [
                    TextSpan(
                      text: DateFormat.MMMd().add_jm().format(
                        reading.recordedAt,
                      ),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

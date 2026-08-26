part of 'doctor_patient_workspace_view.dart';

// ---------------------------------------------------------------------------
// Trends panel â€” sparkline charts for each vital type
// ---------------------------------------------------------------------------

class _TrendsPanel extends StatelessWidget {
  const _TrendsPanel({required this.patientId});
  final String patientId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final readings = StaffState.instance.vitalsForPatient(patientId);

        // Group readings by vital type, keep newest-first order.
        final grouped = <VitalKey, List<StaffPatientVitalReading>>{};
        for (final r in readings) {
          grouped.putIfAbsent(r.vital, () => []).add(r);
        }

        if (grouped.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(title: 'Vital trends', icon: AppIcons.trend),
              GlassCard(
                frosted: true,
                child: Text(
                  'No vital readings recorded yet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(title: 'Vital trends', icon: AppIcons.trend),
            for (final entry in grouped.entries) ...[
              _VitalTrendCard(vitalKey: entry.key, readings: entry.value),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _VitalTrendCard extends StatelessWidget {
  const _VitalTrendCard({required this.vitalKey, required this.readings});

  final VitalKey vitalKey;
  final List<StaffPatientVitalReading> readings;

  // Parse a numeric value from the reading string (handles "120/80" â†’ 120).
  double? _parse(String raw) {
    final s = raw.split('/').first.trim();
    return double.tryParse(s);
  }

  @override
  Widget build(BuildContext context) {
    // Oldest â†’ newest for left-to-right chart direction.
    final ordered = readings.reversed.toList();
    final points = <FlSpot>[];
    for (var i = 0; i < ordered.length && i < 14; i++) {
      final v = _parse(ordered[i].value);
      if (v != null) points.add(FlSpot(i.toDouble(), v));
    }

    final color = vitalKey.accent;
    final latest = readings.first;
    final latestDisplay = latest.value;
    final latestDate = DateFormat.MMMd().add_jm().format(latest.recordedAt);

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(vitalKey.icon, size: 16, color: color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  vitalKey.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              RiskBadge(risk: latest.risk),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                latestDisplay,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                vitalKey.unit,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
              const Spacer(),
              Text(
                latestDate,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            ],
          ),
          if (points.length >= 2) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              height: 72,
              child: LineChart(
                LineChartData(
                  minY:
                      points.map((p) => p.y).reduce((a, b) => a < b ? a : b) *
                      0.95,
                  maxY:
                      points.map((p) => p.y).reduce((a, b) => a > b ? a : b) *
                      1.05,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: points,
                      isCurved: true,
                      color: color,
                      barWidth: 2,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, pct, bar, idx) =>
                            FlDotCirclePainter(
                              radius: 3,
                              color: color,
                              strokeWidth: 0,
                              strokeColor: Colors.transparent,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${points.length} reading${points.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

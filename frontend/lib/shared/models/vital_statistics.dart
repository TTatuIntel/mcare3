import 'vital.dart';

enum VitalTrend { rising, falling, steady, insufficient }

/// A small, reusable statistical summary for one vital over a chosen period.
///
/// Keeping the calculation outside the UI means Home, Vitals and exported
/// reports always describe the same readings in the same way.
class VitalStatistics {
  const VitalStatistics({
    required this.count,
    required this.average,
    required this.lowest,
    required this.highest,
    required this.inRangePercent,
    required this.trend,
  });

  factory VitalStatistics.from(Iterable<VitalReading> source) {
    final readings = source.toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    if (readings.isEmpty) return VitalStatistics.empty;

    final values = readings.map((reading) => reading.value).toList();
    final average = values.reduce((a, b) => a + b) / values.length;
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);
    final inRange = readings
        .where((reading) => reading.risk == RiskLevel.normal)
        .length;

    return VitalStatistics(
      count: readings.length,
      average: average,
      lowest: lowest,
      highest: highest,
      inRangePercent: (inRange / readings.length * 100).round(),
      trend: _trendFor(readings),
    );
  }

  static const empty = VitalStatistics(
    count: 0,
    average: null,
    lowest: null,
    highest: null,
    inRangePercent: null,
    trend: VitalTrend.insufficient,
  );

  final int count;
  final double? average;
  final double? lowest;
  final double? highest;
  final int? inRangePercent;
  final VitalTrend trend;

  static VitalTrend _trendFor(List<VitalReading> readings) {
    if (readings.length < 4) return VitalTrend.insufficient;

    final half = readings.length ~/ 2;
    final older = readings.take(half).map((reading) => reading.value).toList();
    final newer = readings.skip(readings.length - half).map((r) => r.value).toList();
    final olderAverage = older.reduce((a, b) => a + b) / older.length;
    final newerAverage = newer.reduce((a, b) => a + b) / newer.length;
    if (olderAverage == 0) return VitalTrend.steady;

    final change = (newerAverage - olderAverage) / olderAverage.abs();
    if (change > 0.05) return VitalTrend.rising;
    if (change < -0.05) return VitalTrend.falling;
    return VitalTrend.steady;
  }
}

extension VitalTrendLabel on VitalTrend {
  String get label => switch (this) {
    VitalTrend.rising => 'Rising',
    VitalTrend.falling => 'Falling',
    VitalTrend.steady => 'Steady',
    VitalTrend.insufficient => 'Not enough data',
  };
}

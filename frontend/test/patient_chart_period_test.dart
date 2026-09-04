import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/core/api/patient_chart_api.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/patient_chart/patient_chart_widgets.dart';
import 'package:mcare/shared/widgets/period_filter_bar.dart';

void main() {
  group('ChartPeriod', () {
    test('a rolling preset asks the server for days, not dates', () {
      expect(ChartPeriod.month.query, '?days=30');
      expect(ChartPeriod.month.spanDays(), 30);
      expect(ChartPeriod.month.key, 'rolling:30');
    });

    test('a picked range asks for whole days, in order', () {
      final period = ChartPeriod.range(
        DateTime(2026, 8, 20, 14, 30),
        DateTime(2026, 8, 3, 6),
      );

      // Picked backwards — the window still runs forwards.
      expect(period.query, '?from=2026-08-03&to=2026-08-20');
      expect(period.spanDays(), 18);
      expect(period.isCustom, isTrue);
    });

    test('calendar spans land on real month boundaries', () {
      final presets = ChartPeriod.calendarPresets(DateTime(2026, 3, 17));
      final lastMonth = presets.firstWhere((p) => p.presetKey == 'last-month');

      // February 2026 has 28 days, and the span must not spill into March.
      expect(lastMonth.query, '?from=2026-02-01&to=2026-02-28');
      expect(lastMonth.spanDays(), 28);

      final ytd = presets.firstWhere((p) => p.presetKey == 'ytd');
      expect(ytd.query, '?from=2026-01-01&to=2026-03-17');
    });

    test('no calendar span outruns what the endpoint will read', () {
      // 31 December is the longest a year-to-date window ever gets.
      final ytd = ChartPeriod.calendarPresets(
        DateTime(2028, 12, 31),
      ).firstWhere((p) => p.presetKey == 'ytd');

      expect(ytd.spanDays(), lessThanOrEqualTo(ChartPeriod.maxDays));
      for (final preset in ChartPeriod.presets) {
        expect(preset.spanDays(), lessThanOrEqualTo(ChartPeriod.maxDays));
      }
    });

    test('two periods meaning the same window are the same period', () {
      expect(ChartPeriod.month, ChartPeriod.month);
      expect(
        ChartPeriod.range(DateTime(2026, 8, 1), DateTime(2026, 8, 8)),
        ChartPeriod.range(DateTime(2026, 8, 1, 9), DateTime(2026, 8, 8, 17)),
      );
      expect(ChartPeriod.week == ChartPeriod.month, isFalse);
    });
  });

  testWidgets('a blood pressure reading fits a narrow phone', (tester) async {
    // 320 logical pixels wide, inside a sheet's own padding — the case that
    // was overflowing by 30 pixels.
    await _pump(
      tester,
      width: 320,
      child: ChartVitalTile(
        vital: ChartVital(
          key: VitalKey.bloodPressure,
          count: 2,
          points: const [],
          trend: 'up',
          inRangePct: 0,
          // The server's display value already carries the unit.
          latestValue: '172/108 mmHg',
          latestAt: DateTime(2026, 8, 28, 8, 56),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('172/108 mmHg'), findsOneWidget);
    // The unit is printed once, not twice.
    expect(find.text(VitalKey.bloodPressure.unit), findsNothing);
  });

  testWidgets('the period bar never truncates the window it is showing', (
    tester,
  ) async {
    ChartPeriod? chosen;

    await _pump(
      tester,
      width: 360,
      child: PeriodFilterBar(
        period: ChartPeriod.month,
        onChanged: (period) => chosen = period,
      ),
    );

    expect(tester.takeException(), isNull);
    // On a phone the range moves to its own line rather than competing with
    // the pill and the steppers. Squeezed onto one, the two facts this
    // control exists to state came out as "L…" and "Jul 30 – Aug …".
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text(ChartPeriod.month.rangeText), findsOneWidget);
    expect(tester.getSize(find.byType(PeriodFilterBar)).height, lessThan(64));

    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();

    // Presets, calendar spans and a month grid, all in the one sheet.
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.byType(PeriodRangeCalendar), findsOneWidget);

    await tester.tap(find.text('Last 7 days'));
    await tester.pump();
    await tester.ensureVisible(find.text('Apply period'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply period'));
    await tester.pumpAndSettle();

    expect(chosen, ChartPeriod.week);
  });

  testWidgets('a wide chart keeps the whole filter on one line', (
    tester,
  ) async {
    await _pump(
      tester,
      width: 520,
      child: PeriodFilterBar(period: ChartPeriod.month, onChanged: (_) {}),
    );

    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text(ChartPeriod.month.rangeText), findsOneWidget);
    expect(tester.getSize(find.byType(PeriodFilterBar)).height, lessThan(44));
  });

  testWidgets('stepping back moves the window by its own length', (
    tester,
  ) async {
    ChartPeriod? chosen;
    final period = ChartPeriod.range(
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 7),
    );

    await _pump(
      tester,
      width: 360,
      child: PeriodFilterBar(
        period: period,
        onChanged: (value) => chosen = value,
      ),
    );

    await tester.tap(find.byTooltip('Previous 7 days'));
    await tester.pump();

    expect(chosen?.query, '?from=2026-07-25&to=2026-07-31');
  });

  testWidgets('there is no stepping into the future', (tester) async {
    ChartPeriod? chosen;

    await _pump(
      tester,
      width: 360,
      child: PeriodFilterBar(
        // A rolling window always runs up to now.
        period: ChartPeriod.week,
        onChanged: (value) => chosen = value,
      ),
    );

    await tester.tap(find.byTooltip('Next 7 days'));
    await tester.pump();

    expect(chosen, isNull);
  });

  testWidgets('a stat chip carries its count on one line', (tester) async {
    var tapped = false;

    await _pump(
      tester,
      width: 360,
      child: ChartStatChip(
        label: 'alerts',
        value: '2',
        icon: Icons.warning_amber_rounded,
        accent: const Color(0xFFEF4444),
        flag: '2 critical',
        onTap: () => tapped = true,
      ),
    );

    expect(tester.takeException(), isNull);
    // The tile this replaced stacked label, value and caption — three lines.
    expect(tester.getSize(find.byType(ChartStatChip)).height, lessThan(40));

    await tester.tap(find.text('alerts'));
    expect(tapped, isTrue);
  });

  testWidgets('the calendar builds a range from two taps', (tester) async {
    DateTime? start;
    DateTime? end;

    await _pump(
      tester,
      width: 360,
      child: PeriodRangeCalendar(
        firstDate: DateTime(2026, 1, 1),
        lastDate: DateTime(2026, 8, 31),
        start: DateTime(2026, 8, 10),
        end: DateTime(2026, 8, 20),
        onChanged: (from, to) {
          start = from;
          end = to;
        },
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('August 2026'), findsOneWidget);

    // Picked back to front — the calendar still reports it forwards.
    await tester.tap(find.text('14'));
    await tester.pump();
    await tester.tap(find.text('3'));
    await tester.pump();

    expect(start, DateTime(2026, 8, 3));
    expect(end, DateTime(2026, 8, 14));
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  required double width,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

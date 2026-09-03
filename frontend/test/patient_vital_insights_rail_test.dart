import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/patients/vitals/patient_vital_insights.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/state/vitals_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The insights band is one strip of screen, so it has to earn it: what is
/// due, what was last read, what the period says — not a label pointing at a
/// chart. And it has to hold still while it says so.
void main() {
  setUp(() {
    NotificationState.instance.seed([]);
    VitalsState.instance.seedEnabledCatalog(VitalKey.values);
    VitalsState.instance.seedAssigned([VitalKey.bloodPressure]);
    VitalsState.instance.seedTracked([
      VitalKey.bloodPressure,
      VitalKey.heartRate,
    ]);
    VitalsState.instance.seed([
      VitalReading(
        id: 'r1',
        vital: VitalKey.bloodPressure,
        value: 118,
        secondaryValue: 76,
        recordedAt: DateTime.now().subtract(const Duration(hours: 2)),
        risk: RiskLevel.normal,
      ),
    ]);
  });

  tearDown(() {
    VitalsState.instance.seed([]);
    NotificationState.instance.seed([]);
  });

  testWidgets('the first page is the reading nobody has taken yet', (
    tester,
  ) async {
    await _pumpRail(tester);

    // Heart rate is tracked with nothing logged against it, so it leads.
    expect(find.text('Time to record HR'), findsOneWidget);
    expect(find.text('Log now'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('a swipe reaches the last reading and the estimate', (
    tester,
  ) async {
    await _pumpRail(tester);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Blood Pressure'), findsOneWidget);
    expect(find.textContaining('118/76 mmHg'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Health estimate'), findsOneWidget);
    expect(find.textContaining('% in range'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the band left alone does not page under the reader', (
    tester,
  ) async {
    await _pumpRail(tester);
    final headline = tester.getTopLeft(find.text('Time to record HR'));

    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));

    expect(find.text('Time to record HR'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Time to record HR')), headline);

    await _dispose(tester);
  });

  testWidgets('the statistics entry still opens the charts sheet', (
    tester,
  ) async {
    await _pumpRail(tester);

    await tester.tap(find.byKey(const ValueKey('open-vital-insights')));
    await tester.pumpAndSettle();

    expect(find.text('Vital statistics & charts'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('with nothing logged it asks for a first reading', (
    tester,
  ) async {
    VitalsState.instance.seed([]);
    await _pumpRail(tester);

    expect(find.text('No readings yet'), findsOneWidget);
    expect(find.text('2 vitals due'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Health estimate'), findsOneWidget);
    expect(find.textContaining('Log a few readings'), findsOneWidget);

    await _dispose(tester);
  });
}

Future<void> _pumpRail(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: PatientVitalInsightsLauncher(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/patients/vitals/vitals_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/notification_item.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/state/vitals_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The vitals page used to carry three shortcuts where a filter belongs: a
/// fixed "past 7 days" jump, a report button and a link to resolved alerts.
/// None of them filtered anything, so the readings below always showed the
/// same handful whatever the patient wanted to look at.
///
/// What these tests hold to: one window governs the section, the three lenses
/// answer for that window and nothing outside it, a closed alert shows what
/// the care team actually decided, and stepping the window back changes the
/// answer rather than the label.
void main() {
  final now = DateTime.now();

  VitalReading reading(String id, VitalKey vital, double value, int daysAgo) =>
      VitalReading(
        id: id,
        vital: vital,
        value: value,
        recordedAt: now.subtract(Duration(days: daysAgo, hours: 2)),
        risk: RiskLevel.normal,
      );

  setUp(() {
    AuthState.instance.signIn(
      const AppUser(
        id: 'p1',
        uniqueId: 'PT-001',
        firstName: 'Amara',
        lastName: 'Doe',
        email: 'amara@example.com',
        role: UserRole.patient,
      ),
    );

    VitalsState.instance.seedEnabledCatalog(VitalKey.values);
    VitalsState.instance.seedAssigned(const []);
    VitalsState.instance.seedTracked([VitalKey.heartRate, VitalKey.weight]);
    VitalsState.instance.seed([
      reading('r_today', VitalKey.heartRate, 70, 0),
      reading('r_week', VitalKey.heartRate, 74, 5),
      reading('r_weight', VitalKey.weight, 81, 5),
      // Outside three weeks: present in the record, absent from the window.
      reading('r_old', VitalKey.heartRate, 96, 40),
    ]);

    NotificationState.instance.seed([
      AppNotification(
        id: 'a1',
        kind: NotificationKind.vitalAlert,
        title: 'Heart rate high',
        body: 'Heart rate 128 bpm recorded.',
        createdAt: now.subtract(const Duration(days: 4)),
        read: true,
        resolved: true,
        resolvedAt: now.subtract(const Duration(days: 3)),
        actionArguments: VitalKey.heartRate,
        resolvedBy: 'Dr. Kojo Mensah',
        resolutionAction: 'Patient contacted',
        resolutionNote: 'Spoke with Amara — reading taken after climbing '
            'stairs. Repeat at rest tomorrow.',
      ),
      // Closed long before the window opens.
      AppNotification(
        id: 'a_old',
        kind: NotificationKind.vitalAlert,
        title: 'Weight change',
        body: 'Weight up 3 kg.',
        createdAt: now.subtract(const Duration(days: 60)),
        read: true,
        resolved: true,
        resolvedAt: now.subtract(const Duration(days: 58)),
        actionArguments: VitalKey.weight,
        resolvedBy: 'Dr. Kojo Mensah',
        resolutionAction: 'Monitored / observed',
      ),
    ]);
  });

  tearDown(() {
    VitalsState.instance.seed(const []);
    NotificationState.instance.seed(const []);
  });

  testWidgets('opens on a three-week window and says which one', (
    tester,
  ) async {
    await _pumpVitals(tester);

    expect(find.text('Last 3 weeks'), findsOneWidget);
    // Three lenses, one control each. "Resolved" also labels a hero stat, so
    // it is matched where the lens bar puts it.
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(_lens('Resolved'), findsOneWidget);
  });

  testWidgets('Latest shows the newest of each vital, not the newest overall', (
    tester,
  ) async {
    await _pumpVitals(tester);

    // Two tracked vitals in the window, so two rows — the older heart rate
    // reading does not displace weight.
    expect(find.textContaining('Newest of each vital'), findsOneWidget);
    expect(find.textContaining('2 of 3 readings'), findsOneWidget);
  });

  testWidgets('History groups every reading in the window by day', (
    tester,
  ) async {
    await _pumpVitals(tester);
    await tester.tap(find.text('History'));
    await _settle(tester);

    // Three readings inside three weeks across two days; the 40-day-old one
    // is outside the window and is not counted.
    expect(find.textContaining('3 readings across 2 days'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('Resolved shows what the care team decided, in their words', (
    tester,
  ) async {
    await _pumpVitals(tester);
    await tester.tap(_lens('Resolved'));
    await _settle(tester);

    expect(find.textContaining('1 alert reviewed and closed'), findsOneWidget);
    expect(find.text('Patient contacted'), findsOneWidget);
    expect(
      find.textContaining('Repeat at rest tomorrow'),
      findsOneWidget,
    );
    expect(find.textContaining('Dr. Kojo Mensah'), findsWidgets);
    // The alert closed two months ago belongs to a different window.
    expect(find.text('Monitored / observed'), findsNothing);
  });

  testWidgets('stepping the window back changes the answer', (tester) async {
    await _pumpVitals(tester);
    await tester.tap(find.text('History'));
    await _settle(tester);
    expect(find.textContaining('3 readings across 2 days'), findsOneWidget);

    // One step back is the previous three weeks, which holds only the reading
    // the current window was hiding — the window is doing the filtering, not
    // a fixed "last N" cut-off.
    await tester.tap(find.byTooltip('Previous 21 days'));
    await _settle(tester);

    expect(find.textContaining('1 reading across 1 day'), findsOneWidget);
    expect(find.textContaining('3 readings across 2 days'), findsNothing);
  });

  testWidgets('the resolved lens counts what it will show', (tester) async {
    await _pumpVitals(tester);

    // The count sits on the control itself, so the patient can see there is
    // something to read without switching to it first.
    expect(
      find.descendant(
        of: find.ancestor(of: _lens('Resolved'), matching: find.byType(Row)),
        matching: find.text('1'),
      ),
      findsWidgets,
    );
  });
}

/// The lens control called [label], as opposed to a hero stat of the same name.
Finder _lens(String label) => find.descendant(
  of: find.byType(AnimatedContainer),
  matching: find.text(label),
);

Future<void> _pumpVitals(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: const VitalsView()),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Never `pumpAndSettle`: the floating action button breathes forever by
/// design, so settling never completes.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

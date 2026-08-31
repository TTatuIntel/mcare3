import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/patients/dashboard/patient_dashboard_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/vitals_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The home vitals board is the patient's main logging surface: it must show
/// what each tracked vital currently reads, and it must let the patient add
/// vitals to their own plan without going through a clinician.
///
/// Home keeps the board collapsed so the page stays short, so every assertion
/// about a tile runs after the drop-down is opened. What stays visible while
/// it is closed — the statistics strip, the Vitals shortcut and the floating
/// log action — is covered by its own test.
void main() {
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
    VitalsState.instance.seedAssigned([VitalKey.bloodPressure]);
    VitalsState.instance.seedTracked([
      VitalKey.bloodPressure,
      VitalKey.heartRate,
    ]);
    VitalsState.instance.seed([
      VitalReading(
        id: 'r1',
        vital: VitalKey.bloodPressure,
        value: 128,
        secondaryValue: 82,
        recordedAt: DateTime.now().subtract(const Duration(hours: 2)),
        risk: RiskLevel.normal,
      ),
      VitalReading(
        id: 'r2',
        vital: VitalKey.bloodPressure,
        value: 120,
        secondaryValue: 78,
        recordedAt: DateTime.now().subtract(const Duration(days: 1)),
        risk: RiskLevel.normal,
      ),
    ]);
  });

  testWidgets('collapsed board still summarises vitals and offers shortcuts', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    // General statistics stay on screen with the board closed.
    expect(find.text('Tracked'), findsOneWidget);
    expect(find.text('Logged today'), findsOneWidget);
    expect(find.text('Need review'), findsOneWidget);

    // Both quick routes out of the collapsed card, plus the floating action.
    expect(find.text('Go to vitals'), findsOneWidget);
    expect(find.text('Quick log'), findsOneWidget);
    expect(find.text('Log vital'), findsOneWidget);

    // The tiles themselves are not paid for until the patient opens the board.
    expect(find.text('Add a vital'), findsNothing);
    expect(find.text('Care team'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('board shows each tracked vital with its latest reading', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await _expandBoard(tester);

    expect(find.text('Record a vital'), findsOneWidget);
    expect(find.text('2 tracked'), findsOneWidget);

    // Assigned vital renders its latest value, its source and a log action.
    expect(find.text('BP'), findsWidgets);
    expect(find.textContaining('128/82'), findsWidgets);
    expect(find.text('Care team'), findsWidgets);

    // A self-tracked vital with no reading still invites a first entry.
    expect(find.text('HR'), findsWidgets);
    expect(find.text('Self-tracked'), findsWidgets);
    expect(find.text('Not logged yet'), findsWidgets);

    await _dispose(tester);
  });

  testWidgets('patient can self-assign more vitals from home', (tester) async {
    await _pumpDashboard(tester);
    await _expandBoard(tester);

    expect(find.text('Add a vital'), findsOneWidget);
    await tester.tap(find.text('Add a vital'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Your tracked vitals'), findsOneWidget);
    expect(find.text('Optional vitals'), findsOneWidget);
    // Doctor-assigned vitals stay locked to the care team.
    expect(find.text('Required by your care team'), findsWidgets);

    await _dispose(tester);
  });
}

Future<void> _pumpDashboard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Overflows are deliberately NOT swallowed here. The one this used to hide
  // was real: the patient header's fallback subtitle had no maxLines, so
  // adding an action to the row wrapped it to two lines and burst the fixed
  // 68px header. Let layout errors fail the test.
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: const PatientDashboardView()),
  );
  // Let the staggered entry animations (and their timers) run out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Opens the home vitals drop-down, which starts collapsed.
Future<void> _expandBoard(WidgetTester tester) async {
  await tester.tap(find.text('Quick log'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tears the tree down so the dashboard's auto-paging timers are cancelled.
Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

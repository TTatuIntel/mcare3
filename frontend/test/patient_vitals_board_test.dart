import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/patients/dashboard/patient_dashboard_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/vitals_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The upgraded home keeps repeated health detail off the dashboard. Vitals
/// remain one tap away through search and the compact Log vital action.
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

  testWidgets('home exposes the compact quick actions patients use most', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Appointments'), findsOneWidget);
    expect(find.text('Medications'), findsOneWidget);
    expect(find.text('Log vital'), findsOneWidget);
    expect(find.text('Meals'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
    expect(find.text('Emergency'), findsOneWidget);

    // The old detail board and its duplicate calls-to-action are gone.
    expect(find.text('Go to vitals'), findsNothing);
    expect(find.text('Quick log'), findsNothing);
    expect(find.text('Add a vital'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('Log vital opens the existing multi-vital flow', (tester) async {
    await _pumpDashboard(tester);
    await tester.tap(find.text('Log vital'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Log vitals'), findsOneWidget);
    expect(find.text('Your tracked vitals'), findsOneWidget);
    expect(find.text('BP'), findsWidgets);
    expect(find.text('HR'), findsWidgets);

    await _dispose(tester);
  });

  testWidgets('dashboard search finds functionality by plain language', (
    tester,
  ) async {
    await _pumpDashboard(tester);
    await tester.tap(find.textContaining('Search vitals'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField), 'urgent help');
    await tester.pump();

    expect(find.text('Emergency SOS'), findsOneWidget);
    expect(find.text('Get urgent help now'), findsOneWidget);
    expect(find.text('Appointments'), findsNothing);

    await tester.enterText(find.byType(TextField), 'upload');
    await tester.pump();
    expect(find.text('Documents & uploads'), findsOneWidget);
    expect(find.text('Open results, reports and files'), findsOneWidget);

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

/// Tears the tree down so the dashboard's auto-paging timer is cancelled.
Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

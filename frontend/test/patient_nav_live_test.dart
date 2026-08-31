import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/main.dart';
import 'package:mcare/patients/hubs/patient_health_hub_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/bootstrap/app_bootstrap.dart';
import 'package:mcare/shared/bootstrap/launch_readiness.dart';
import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/medication.dart';
import 'package:mcare/shared/models/notification_item.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/navigation/patient_nav_badges.dart';
import 'package:mcare/shared/navigation/root_navigator.dart';
import 'package:mcare/shared/state/medications_state.dart';
import 'package:mcare/shared/state/messages_state.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/nav_badge.dart';
import 'package:mcare/shared/widgets/patient_bottom_nav.dart';

/// The patient's bottom nav is their map of the app, so two things have to
/// hold: every tab leads somewhere real, and each one says what is waiting
/// behind it as soon as it lands — not the next time the patient happens to
/// open that tab.
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
    MedicationsState.instance.seed(meds: const [], doses: const []);
    MessagesState.instance.seed(conversations: const [], threads: const {});
    NotificationState.instance.seed([]);
  });

  tearDown(() {
    MedicationsState.instance.seed(meds: const [], doses: const []);
    NotificationState.instance.seed([]);
  });

  testWidgets('every tab in the bottom nav resolves to a real page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    AppBootstrap.fastMode = true;
    LaunchReadiness.instance.reset();
    await tester.pumpWidget(const McareApp());
    await tester.pump(const Duration(seconds: 1));

    for (final destination in PatientBottomNav.destinations) {
      rootNavigatorKey.currentState!.pushNamed(destination.route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
        find.text('Page not found'),
        findsNothing,
        reason:
            '${destination.label} (${destination.route}) has no route case, '
            'so the tab lands on the not-found page',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a dose that comes due badges the Health tab without a reload', (
    tester,
  ) async {
    await _pumpHealthHub(tester);

    // Nothing outstanding: no badge anywhere.
    expect(find.byType(NavBadge), findsNothing);

    // A dose lands from the poller while the patient is looking at the page.
    MedicationsState.instance.seed(
      meds: const [],
      doses: [
        MedicationDose(
          id: 'd1',
          medicationId: 'm1',
          name: 'Metformin',
          dosage: '500 mg',
          scheduledAt: DateTime.now().subtract(const Duration(hours: 1)),
          status: DoseStatus.pending,
        ),
      ],
    );
    await tester.pump();

    // The tab and the tile behind it, showing the same number.
    expect(find.byType(NavBadge), findsNWidgets(2));
    expect(_badgeText('1'), findsNWidgets(2));
  });

  testWidgets('a dose scheduled for later tonight is not yet a badge', (
    tester,
  ) async {
    MedicationsState.instance.seed(
      meds: const [],
      doses: [
        MedicationDose(
          id: 'd1',
          medicationId: 'm1',
          name: 'Metformin',
          dosage: '500 mg',
          scheduledAt: DateTime.now().add(const Duration(minutes: 90)),
          status: DoseStatus.pending,
        ),
      ],
    );
    await _pumpHealthHub(tester);

    expect(find.byType(NavBadge), findsNothing);
  });

  testWidgets('unread notifications badge the tab that holds the inbox', (
    tester,
  ) async {
    await _pumpHealthHub(tester);
    expect(find.byType(NavBadge), findsNothing);

    NotificationState.instance.seed([
      _notification('n1'),
      _notification('n2'),
    ]);
    await tester.pump();

    // More holds Notifications, so exactly one tab badges — not Health. The
    // header bell shows the same 2, hence matching inside the badge only.
    expect(find.byType(NavBadge), findsOneWidget);
    expect(_badgeText('2'), findsOneWidget);
  });

  test('Home is never badged, however much is waiting', () {
    NotificationState.instance.seed([_notification('n1')]);
    MedicationsState.instance.seed(
      meds: const [],
      doses: [
        MedicationDose(
          id: 'd1',
          medicationId: 'm1',
          name: 'Metformin',
          dosage: '500 mg',
          scheduledAt: DateTime.now().subtract(const Duration(hours: 1)),
          status: DoseStatus.pending,
        ),
      ],
    );

    expect(PatientNavBadges.forRoute(RouteNames.patientDashboard), 0);
    expect(PatientNavBadges.forRoute(RouteNames.patientHealth), 1);
    expect(PatientNavBadges.forRoute(RouteNames.patientMore), 1);
  });
}

Finder _badgeText(String value) =>
    find.descendant(of: find.byType(NavBadge), matching: find.text(value));

AppNotification _notification(String id) => AppNotification(
  id: id,
  title: 'Reading due',
  body: 'Record your blood pressure.',
  createdAt: DateTime.now(),
  kind: NotificationKind.medication,
);

Future<void> _pumpHealthHub(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: const PatientHealthHubView()),
  );
  await tester.pump();
}

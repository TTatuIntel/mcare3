import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/core/realtime/session_poller.dart';
import 'package:mcare/patients/dashboard/patient_dashboard_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/announcement.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/appointment.dart';
import 'package:mcare/shared/models/meal_plan.dart';
import 'package:mcare/shared/models/medication.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/announcements_state.dart';
import 'package:mcare/shared/state/appointments_state.dart';
import 'package:mcare/shared/state/meal_plans_state.dart';
import 'package:mcare/shared/state/medications_state.dart';
import 'package:mcare/shared/state/messages_state.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/state/sos_state.dart';
import 'package:mcare/shared/state/support_state.dart';
import 'package:mcare/shared/state/vital_report_state.dart';
import 'package:mcare/shared/state/vitals_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The head of the patient home is a briefing written on the page background:
/// what today is asking, the counted facts, and the steps themselves.
///
/// What these tests hold to: nothing moves on its own, nothing is hidden
/// behind a timer, the steps are reachable the moment the page is drawn, the
/// counted facts are tappable, and the page keeps the same height while it is
/// simply being looked at — the regression that made the old rotating card
/// unusable to read.
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

    final now = DateTime.now();

    VitalsState.instance.seedEnabledCatalog(VitalKey.values);
    VitalsState.instance.seedAssigned([VitalKey.bloodPressure]);
    VitalsState.instance.seedTracked([VitalKey.bloodPressure]);
    VitalsState.instance.seed([]);

    AppointmentsState.instance.seed([]);
    MedicationsState.instance.seed(meds: const [], doses: const []);
    NotificationState.instance.seed([]);
    MessagesState.instance.seed(conversations: const [], threads: const {});
    SupportState.instance.seed([]);
    VitalReportState.instance.seed([]);
    SosState.instance.seed(contacts: const [], history: const []);

    AnnouncementsState.instance.seed([
      AppAnnouncement(
        id: 'a1',
        title: 'Clinic hours extended',
        body: 'Open until 8:00 PM this week.',
        createdAt: now.subtract(const Duration(hours: 2)),
        createdBy: 'mCare Admin',
      ),
    ]);

    MealPlansState.instance.seed([
      StaffMealPlan(
        id: 'm1',
        patientId: 'p1',
        patientName: 'Amara Doe',
        title: 'Oats with berries',
        mealType: MealType.breakfast,
        calories: 320,
        assignedAt: now,
        assignedBy: 'Dr. Mensah',
      ),
    ]);
  });

  tearDown(() {
    AnnouncementsState.instance.seed(const []);
    MealPlansState.instance.seed(const []);
    MedicationsState.instance.seed(meds: const [], doses: const []);
    AppointmentsState.instance.seed(const []);
  });

  testWidgets('the day is stated once, and the steps are already there', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    // One headline, counted from the steps themselves.
    expect(find.text('1 step today'), findsOneWidget);
    expect(find.text('Nothing is overdue.'), findsOneWidget);

    // The step is on the page, not behind a dwell.
    expect(find.text('Record your vitals'), findsWidgets);
    expect(
      find.ancestor(
        of: find.text('Record your vitals').first,
        matching: find.byType(InkWell),
      ),
      findsWidgets,
    );

    // Nothing claims to be moving, because nothing is.
    expect(find.text('Live'), findsNothing);
    expect(find.text('Swipe'), findsNothing);

    await _dispose(tester);
  });

  testWidgets('a page left alone does not move under the reader', (
    tester,
  ) async {
    MedicationsState.instance.seed(
      meds: const [],
      doses: [
        MedicationDose(
          id: 'd1',
          medicationId: 'med1',
          name: 'Metformin',
          dosage: '500 mg',
          scheduledAt: DateTime.now().subtract(const Duration(hours: 1)),
          status: DoseStatus.pending,
        ),
      ],
    );

    await _pumpDashboard(tester);

    final before = tester.getSize(find.byType(PatientDashboardView)).height;
    final headlineAt = tester.getTopLeft(find.text('2 steps today'));

    // Two of the old dwells and then some: the surface that used to re-deal
    // itself every six seconds now holds still.
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 7));

    expect(tester.getSize(find.byType(PatientDashboardView)).height, before);
    expect(tester.getTopLeft(find.text('2 steps today')), headlineAt);
    expect(find.text('Take Metformin'), findsWidgets);

    await _dispose(tester);
  });

  testWidgets('what is past due is said in the headline', (tester) async {
    // A critical reading with no answer from the care team: an urgent scene.
    VitalsState.instance.seed([
      VitalReading(
        id: 'v1',
        vital: VitalKey.bloodPressure,
        value: 186,
        secondaryValue: 118,
        recordedAt: DateTime.now().subtract(const Duration(minutes: 20)),
        risk: RiskLevel.critical,
      ),
    ]);

    await _pumpDashboard(tester);

    expect(
      find.text('1 thing needs attention now — it is first below.'),
      findsOneWidget,
    );

    VitalsState.instance.seed([]);
    await _dispose(tester);
  });

  testWidgets('the counted facts are text you can tap, not cards', (
    tester,
  ) async {
    final now = DateTime.now();
    MedicationsState.instance.seed(
      meds: const [],
      doses: [
        MedicationDose(
          id: 'd1',
          medicationId: 'med1',
          name: 'Metformin',
          dosage: '500 mg',
          scheduledAt: now.add(const Duration(hours: 2)),
          status: DoseStatus.pending,
        ),
      ],
    );
    AppointmentsState.instance.seed([
      Appointment(
        id: 'ap1',
        doctorId: 'dr1',
        doctorName: 'Dr. Kojo Mensah',
        doctorSpecialty: 'Cardiology',
        scheduledAt: now.add(const Duration(days: 1)),
        type: AppointmentType.virtual,
        status: AppointmentStatus.confirmed,
      ),
    ]);

    await _pumpDashboard(tester);

    // Every count the day holds, each one a route into the screen it came
    // from. The semantics carry the label so a screen reader reads a button.
    for (final label in const ['Vitals 0/1', 'Doses 0/1']) {
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.button == true &&
              widget.properties.label == label,
        ),
        findsOneWidget,
        reason: '$label should be a tappable fact',
      );
    }

    await _dispose(tester);
  });

  testWidgets('a day with nothing outstanding is allowed to say so', (
    tester,
  ) async {
    // The one tracked vital is already logged, so "log a reading" is a
    // standing offer rather than a step today.
    VitalsState.instance.seed([
      VitalReading(
        id: 'v1',
        vital: VitalKey.bloodPressure,
        value: 118,
        secondaryValue: 76,
        recordedAt: DateTime.now(),
        risk: RiskLevel.normal,
      ),
    ]);

    await _pumpDashboard(tester);

    expect(find.text('Nothing needs you right now'), findsOneWidget);
    expect(find.text('Log a reading whenever you are ready.'), findsOneWidget);

    // The offer is still on the page — not counted, not hidden.
    expect(find.text('Record your vitals'), findsWidgets);

    VitalsState.instance.seed([]);
    await _dispose(tester);
  });

  testWidgets('a scene that only reports something is not a button', (
    tester,
  ) async {
    await _pumpDashboard(tester);

    // The tally reports; it does not ask, so it carries no ink.
    final tally = find.text('Today\'s progress');
    expect(tally, findsOneWidget);
    expect(
      find.ancestor(of: tally, matching: find.byType(InkWell)),
      findsNothing,
    );

    await _dispose(tester);
  });
}

Future<void> _pumpDashboard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: const PatientDashboardView()),
  );
  // Let the staggered entry animations run out. Never pumpAndSettle: the
  // dashboard's floating button cycles its colours forever by design.
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }

  // These tests push fake time past the session poller's first tick, which
  // would try to reach the network. The page reads stores, not the wire.
  SessionPoller.instance.detach();
}

Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

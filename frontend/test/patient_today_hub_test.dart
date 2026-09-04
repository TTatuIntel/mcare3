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
    // No joining date: an account whose age the server never told us is not
    // new, so the welcome stays out of the tests that are not about it.
    AuthState.instance.signIn(_patient());

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

    // One headline, counted from the steps themselves: a reading to log, a
    // notice to read, a meal to look at and a profile to finish.
    expect(find.text('4 steps today'), findsOneWidget);
    expect(find.text('Nothing is overdue.'), findsOneWidget);

    // The steps are on the page, not behind a dwell, and they come from
    // different parts of the app rather than from vitals alone.
    expect(find.text('Record your vitals'), findsWidgets);
    expect(find.text('Read announcement'), findsWidgets);
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
    final headlineAt = tester.getTopLeft(_headline);

    // Two of the old dwells and then some: the surface that used to re-deal
    // itself every six seconds now holds still.
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 7));

    expect(tester.getSize(find.byType(PatientDashboardView)).height, before);
    expect(tester.getTopLeft(_headline), headlineAt);
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

  testWidgets('the counted facts are tappable, and the rows are one size', (
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

    // Every count the day holds is a route into the screen it came from. The
    // semantics carry the label, so a screen reader reads a button.
    for (final label in const ['Vitals 0/1', 'Doses 0/1']) {
      expect(
        _tappable(label),
        findsOneWidget,
        reason: '$label should be a tappable fact',
      );
    }

    // The steps are rows of one size, so a step clearing swaps a row for a
    // row and the page keeps its shape — whichever steps the day holds.
    final rows = _stepRows;
    expect(rows, findsNWidgets(3));
    final heights = tester
        .widgetList(rows)
        .map((row) => tester.getSize(find.byWidget(row)).height)
        .toSet();
    expect(heights, hasLength(1), reason: 'every step row is one height');

    // The most overdue leads, and the patient's own reading is never rotated
    // out from under them.
    expect(_startingWith('Take Metformin.'), findsOneWidget);
    expect(_startingWith('Record your vitals.'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('a standing offer is not counted as a step', (tester) async {
    await _pumpDashboard(tester);
    final before = _headlineCount(tester);

    // The one tracked vital is now logged, so "log a reading" becomes a
    // standing offer rather than something today is waiting on.
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
    await tester.pump();

    expect(
      _headlineCount(tester),
      before - 1,
      reason: 'a logged reading stops being counted',
    );

    // The offer is still on the page — not counted, not hidden.
    expect(find.text('Record your vitals'), findsWidgets);

    VitalsState.instance.seed([]);
    await _dispose(tester);
  });

  testWidgets('a new account is welcomed, and only for three days', (
    tester,
  ) async {
    AuthState.instance.signIn(_patient(joinedAt: DateTime.now()));

    await _pumpDashboard(tester);

    expect(find.text('See what mCare can do'), findsWidgets);
    expect(find.text('Welcome to mCare, Amara'), findsWidgets);

    // The welcome opens the app itself: every area named in it is a row that
    // goes there.
    await tester.tap(find.text('See what mCare can do').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    for (final area in const ['Vitals', 'Medications', 'Meals', 'Messages']) {
      expect(
        find.text(area),
        findsWidgets,
        reason: '$area should be reachable from the welcome',
      );
    }
    Navigator.of(tester.element(find.text('Medications').first)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await _dispose(tester);
  });

  testWidgets('a fourth-day account is not welcomed again', (tester) async {
    AuthState.instance.signIn(
      _patient(joinedAt: DateTime.now().subtract(const Duration(days: 4))),
    );

    await _pumpDashboard(tester);

    expect(find.text('See what mCare can do'), findsNothing);
    expect(find.textContaining('Welcome to mCare'), findsNothing);

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

AppUser _patient({DateTime? joinedAt}) => AppUser(
  id: 'p1',
  uniqueId: 'PT-001',
  firstName: 'Amara',
  lastName: 'Doe',
  email: 'amara@example.com',
  role: UserRole.patient,
  joinedAt: joinedAt,
);

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

/// The briefing's headline, whatever number the day put in it.
final Finder _headline = find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      RegExp(r'^\d+ steps? today$').hasMatch(widget.data ?? ''),
);

/// Every step row currently drawn in the briefing.
final Finder _stepRows = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_HubStepRow',
);

/// The number the headline is counting.
int _headlineCount(WidgetTester tester) {
  final text = tester.widget<Text>(_headline).data!;
  return int.parse(RegExp(r'^(\d+)').firstMatch(text)!.group(1)!);
}

/// A step row, matched on the title its screen-reader label opens with.
Finder _startingWith(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      (widget.properties.label ?? '').startsWith(prefix),
);

/// A tappable part of the briefing, found the way a screen reader finds it.
Finder _tappable(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == label,
);

Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

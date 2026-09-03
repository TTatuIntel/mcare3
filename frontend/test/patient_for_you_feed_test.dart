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

/// "For you" is the patient's stream. What these tests hold to:
///
///   * it leads with what is wrong, then with what is due, then with what is
///     new, and closes on the quiet tally;
///   * the same thing is never listed twice, however many stores mention it;
///   * a stream that fits on one page is on the page — no window, no folded
///     remainder, and nothing that moves on its own. (Past thirteen rows the
///     tail waits behind a "show more" the patient asks for; these fixtures
///     stay under that line on purpose.)
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
    VitalsState.instance.seedTracked([VitalKey.bloodPressure]);
    VitalsState.instance.seed([]);

    AppointmentsState.instance.seed([]);
    MedicationsState.instance.seed(meds: const [], doses: const []);
    NotificationState.instance.seed([]);
    MessagesState.instance.seed(conversations: const [], threads: const {});
    SupportState.instance.seed([]);
    VitalReportState.instance.seed([]);
    SosState.instance.seed(contacts: const [], history: const []);
    AnnouncementsState.instance.seed(const []);
    MealPlansState.instance.seed(const []);
  });

  tearDown(() {
    AnnouncementsState.instance.seed(const []);
    MealPlansState.instance.seed(const []);
    MedicationsState.instance.seed(meds: const [], doses: const []);
    AppointmentsState.instance.seed(const []);
    VitalsState.instance.seed([]);
  });

  testWidgets('what is wrong leads, then what is due, then what is new', (
    tester,
  ) async {
    final now = DateTime.now();

    // A reading out of range, logged today so the vitals reminder stays quiet
    // and the ordering under test is the only thing on screen.
    VitalsState.instance.seed([
      VitalReading(
        id: 'v1',
        vital: VitalKey.bloodPressure,
        value: 186,
        secondaryValue: 118,
        recordedAt: now.subtract(const Duration(minutes: 30)),
        risk: RiskLevel.critical,
      ),
    ]);
    _seedOverdueDose(now);
    _seedAnnouncement(now, id: 'a1', title: 'Clinic hours extended');

    await _pumpDashboard(tester);

    // Alert, then reminder, then update, then the tally that only reports.
    _expectOrder(tester, const [
      'Care alert',
      'Medicine time',
      'Announcement',
      'Today\'s progress',
    ]);

    await _dispose(tester);
  });

  testWidgets('an overdue dose stays a reminder, above what is merely new', (
    tester,
  ) async {
    final now = DateTime.now();
    _seedOverdueDose(now);
    _seedAnnouncement(now, id: 'a1', title: 'Clinic hours extended');

    await _pumpDashboard(tester);

    expect(_inFeed('Reminder'), findsWidgets);
    _expectOrder(tester, const ['Medicine time', 'Announcement']);

    await _dispose(tester);
  });

  testWidgets('the same thing is never listed twice', (tester) async {
    final now = DateTime.now();
    // Two records of the same notice. Different ids, identical wording — the
    // feed keeps one row.
    _seedAnnouncement(now, id: 'a1', title: 'Clinic hours extended');
    _seedAnnouncement(
      now,
      id: 'a2',
      title: 'Clinic hours extended',
      append: true,
    );

    await _pumpDashboard(tester);

    expect(_inFeed('Announcement'), findsOneWidget);
    expect(_inFeed('Clinic hours extended'), findsOneWidget);

    await _dispose(tester);
  });

  testWidgets('the whole stream is on the page, and it holds still', (
    tester,
  ) async {
    _seedLongStream();

    await _pumpDashboard(tester);

    // Six rows — under the thirteen-row page — so every one is laid out,
    // including the last. Nothing is behind a "show more" control at this
    // length, and nothing is waiting for a timer to bring it round.
    _expectOrder(tester, const [
      'Care alert',
      'Medicine time',
      'Next appointment',
      'Assigned meal',
      'Announcement',
      "Today's progress",
    ]);
    expect(find.byTooltip('Pause auto-scroll'), findsNothing);
    expect(find.textContaining('Show '), findsNothing);

    // Left alone, the rows stay exactly where they were drawn.
    final before = tester.getTopLeft(_inFeed('Medicine time'));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 6));
    expect(tester.getTopLeft(_inFeed('Medicine time')), before);

    await _dispose(tester);
  });

  testWidgets('with animations off the page reads the same', (tester) async {
    _seedLongStream();

    await _pumpDashboard(tester, reduceMotion: true);

    // There is no reduced-motion variant any more, because there is no motion:
    // the same rows, in the same order, either way.
    expect(_inFeed('Care alert'), findsOneWidget);

    expect(_inFeed('Today\'s progress'), findsOneWidget);

    await _dispose(tester);
  });
}

// ── Seeds ────────────────────────────────────────────────────────────────────

void _seedOverdueDose(DateTime now) {
  MedicationsState.instance.seed(
    meds: const [],
    doses: [
      MedicationDose(
        id: 'd1',
        medicationId: 'med1',
        name: 'Metformin',
        dosage: '500 mg',
        scheduledAt: now.subtract(const Duration(hours: 1)),
        status: DoseStatus.pending,
      ),
    ],
  );
}

void _seedAnnouncement(
  DateTime now, {
  required String id,
  required String title,
  bool append = false,
}) {
  final existing = append
      ? AnnouncementsState.instance.live.toList()
      : <AppAnnouncement>[];
  AnnouncementsState.instance.seed([
    ...existing,
    AppAnnouncement(
      id: id,
      title: title,
      body: 'Open until 8:00 PM this week.',
      createdAt: now.subtract(const Duration(hours: 2)),
      createdBy: 'mCare Admin',
    ),
  ]);
}

/// Enough distinct things to overflow the five-row window.
void _seedLongStream() {
  final now = DateTime.now();
  VitalsState.instance.seed([
    VitalReading(
      id: 'v1',
      vital: VitalKey.bloodPressure,
      value: 186,
      secondaryValue: 118,
      recordedAt: now.subtract(const Duration(days: 1)),
      risk: RiskLevel.critical,
    ),
  ]);
  _seedOverdueDose(now);
  _seedAnnouncement(now, id: 'a1', title: 'Clinic hours extended');
  AppointmentsState.instance.seed([
    Appointment(
      id: 'ap1',
      doctorId: 'dr1',
      doctorName: 'Dr. Kojo Mensah',
      doctorSpecialty: 'Cardiology',
      scheduledAt: now.add(const Duration(days: 1)),
      type: AppointmentType.virtual,
      status: AppointmentStatus.confirmed,
      reason: 'Blood pressure review',
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
}

// ── Finders ──────────────────────────────────────────────────────────────────

/// The rows of the stream. Scoped deliberately: the briefing at the top of the
/// page is built from the same scenes, so a title or a detail line can
/// honestly appear in both places, and only one of them is under test here.
final Finder _feedRows = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_FeedRow',
);

Finder _inFeed(String text) =>
    find.descendant(of: _feedRows, matching: find.text(text));

/// Asserts the rows appear top to bottom in the order given.
void _expectOrder(WidgetTester tester, List<String> titles) {
  var previous = double.negativeInfinity;
  for (final title in titles) {
    final finder = _inFeed(title);
    expect(finder, findsOneWidget, reason: '"$title" should be in the feed');
    final top = tester.getTopLeft(finder).dy;
    expect(top, greaterThan(previous), reason: '"$title" is out of order');
    previous = top;
  }
}

// ── Harness ──────────────────────────────────────────────────────────────────

Future<void> _pumpDashboard(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  // Tall enough that the whole home page is laid out on screen, so a tap
  // lands where the patient would put it.
  await tester.binding.setSurfaceSize(const Size(900, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: reduceMotion
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child ?? const SizedBox.shrink(),
            )
          : null,
      home: const PatientDashboardView(),
    ),
  );
  // Let the staggered entry animations run out. Never pumpAndSettle: the
  // floating action button cycles its colours forever by design.
  await tester.pump();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }

  SessionPoller.instance.detach();
}

/// Tears the tree down and checks nothing was thrown on the way.
Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

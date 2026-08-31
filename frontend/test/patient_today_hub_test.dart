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
import 'package:mcare/shared/widgets/glass_card.dart';

/// The home hub is one card that becomes each thing today holds in turn: the
/// title, the accent, the body and the actions change together, so the patient
/// reads "Medicine time" or "Assigned meal", not a fixed panel with a changing
/// row inside it.
///
/// What these tests hold to: the card renames itself as it turns, the most
/// urgent thing leads, a scene that only reports something is not a button,
/// and with animations off nothing hides behind a timer.
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

  testWidgets('the card renames itself as it turns', (tester) async {
    await _pumpDashboard(tester);

    // Opens on the plan — the overview the focused scenes come from.
    expect(_showing(tester, 'Your plan today'), isTrue);
    expect(find.text('Record your vitals'), findsWidgets);
    expect(find.text('Live'), findsOneWidget);

    await _nextScene(tester);

    // A different card entirely: new title, new accent line, new body.
    expect(_showing(tester, 'Your plan today'), isFalse);
    expect(_showing(tester, 'Announcement'), isTrue);
    expect(_showing(tester, 'Clinic hours extended'), isTrue);

    await _nextScene(tester);

    expect(_showing(tester, 'Assigned meal'), isTrue);
    expect(_showing(tester, 'Calories 320'), isTrue);
    expect(_showing(tester, 'Announcement'), isFalse);

    await _dispose(tester);
  });

  testWidgets('a dose that is past due leads, and says so', (tester) async {
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

    // Outranks the plan: the card opens as the thing that is late.
    expect(_showing(tester, 'Medicine time'), isTrue);
    expect(_showing(tester, 'Metformin · past due'), isTrue);
    expect(find.text('Take Metformin'), findsWidgets);
    expect(_showing(tester, 'Your plan today'), isFalse);

    await _dispose(tester);
  });

  testWidgets('the richest scenes fit the card', (tester) async {
    // Two doses due, a visit, an unread thread and a report request: every
    // scene shape the hub can build, including the two-action ones.
    final now = DateTime.now();
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
          instructions: 'Take with food, and drink a full glass of water.',
        ),
        MedicationDose(
          id: 'd2',
          medicationId: 'med2',
          name: 'Amlodipine',
          dosage: '5 mg',
          scheduledAt: now.add(const Duration(hours: 3)),
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
        reason: 'Blood pressure review after the last set of readings',
      ),
    ]);

    await _pumpDashboard(tester);

    // Walk every scene; an overflow anywhere fails on the exception check.
    for (var i = 0; i < 8; i++) {
      expect(tester.takeException(), isNull);
      await _nextScene(tester);
    }

    // The deck sizes to its tallest scene, so the card is the same height on
    // every turn — the page below never jumps.
    final heights = <double>{};
    for (var i = 0; i < 4; i++) {
      heights.add(tester.getSize(_hubCard).height);
      await _nextScene(tester);
    }
    expect(heights, hasLength(1));

    await _dispose(tester);
  });

  testWidgets('a scene that only reports something is not a button', (
    tester,
  ) async {
    // Listed rather than rotated, so every scene is on screen at once and the
    // assertion is about the card, not about timing.
    await _pumpDashboard(tester, reduceMotion: true);

    // Actionable: the plan's step carries ink.
    expect(
      find.ancestor(
        of: find.text('Record your vitals'),
        matching: find.byType(InkWell),
      ),
      findsWidgets,
    );

    // The tally reports; it does not ask.
    final tally = find.text('Today\'s progress');
    expect(tally, findsOneWidget);
    expect(
      find.ancestor(of: tally, matching: find.byType(InkWell)),
      findsNothing,
    );

    await _dispose(tester);
  });

  testWidgets('with animations off the day is listed, not rotated', (
    tester,
  ) async {
    await _pumpDashboard(tester, reduceMotion: true);

    // Nothing is moving, so nothing claims to be.
    expect(find.text('Live'), findsNothing);

    // Every scene the rotation would have taken in turn is reachable at once,
    // each still carrying its own title.
    expect(find.text('Your plan today'), findsOneWidget);
    expect(find.text('Announcement'), findsOneWidget);
    expect(find.text('Assigned meal'), findsOneWidget);
    expect(find.textContaining('Welcome back'), findsOneWidget);

    await _dispose(tester);
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: reduceMotion
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            )
          : null,
      home: const PatientDashboardView(),
    ),
  );
  // Let the staggered entry animations run out. Never pumpAndSettle: the live
  // badge pulses forever by design.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));

  // These tests push fake time past the session poller's first tick, which
  // would try to reach the network. The hub reads stores, not the wire.
  SessionPoller.instance.detach();
}

/// The hub card itself — the one carrying the live badge.
final Finder _hubCard = find
    .ancestor(of: find.text('Live'), matching: find.byType(GlassCard))
    .first;

/// Whether [text] belongs to the scene the deck is currently showing.
///
/// Every scene stays in the tree — that is what makes the card as tall as its
/// tallest scene — so "is it on screen" is a question about the slot's
/// opacity, not about the finder matching.
bool _showing(WidgetTester tester, String text) {
  final finder = find.ancestor(
    of: find.text(text),
    matching: find.byType(AnimatedOpacity),
  );
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<AnimatedOpacity>(finder.first).opacity == 1;
}

/// Waits out one dwell and the page transition that follows it.
Future<void> _nextScene(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tears the tree down so the hub's rotation timers are cancelled.
Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

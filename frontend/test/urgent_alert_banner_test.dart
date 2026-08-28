import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/alerts/alert_center.dart';
import 'package:mcare/shared/alerts/urgent_alerts_card.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/services/sos_ring_service.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/critical_event_overlay.dart';

/// Staff used to be met on sign-in by a full-screen modal that covered the
/// page they had just navigated to, and — because the escalation ladder
/// re-presents unattended work — tore itself down and rebuilt over whatever
/// they did next. Alerts now arrive as tappable notifications instead.
///
/// These pin the properties that matter clinically: nothing is hidden, and
/// nothing is blocked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StaffPatient patient(String id) => StaffPatient(
    id: id,
    name: 'Patient $id',
    age: 40,
    sex: 'F',
    condition: 'Hypertension',
    risk: RiskLevel.normal,
    lastReading: DateTime.now(),
    assignedDoctor: 'Dr. Test',
  );

  StaffAlert alert(String id, {RiskLevel severity = RiskLevel.critical}) =>
      StaffAlert(
        id: id,
        patientId: 'p1',
        patientName: 'Patient p1',
        vital: VitalKey.bloodPressure,
        value: '190/120',
        severity: severity,
        createdAt: DateTime.now(),
      );

  void seed(List<StaffAlert> alerts) {
    StaffState.instance.seedFromApi(
      patients: [patient('p1')],
      alerts: alerts,
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      sosEvents: const [],
    );
  }

  setUp(() {
    AlertCenter.instance.reset();
    AuthState.instance.signIn(
      AppUser(
        id: 'u1',
        uniqueId: 'MCR-000001',
        firstName: 'Test',
        lastName: 'Admin',
        email: 'admin@mcare.health',
        role: UserRole.admin,
      ),
    );
  });

  tearDown(() {
    AlertCenter.instance.reset();
    StaffState.instance.clear();
  });

  /// Mounts a page under the alert layer, with a button that records taps so
  /// a test can prove the page underneath is still reachable.
  Future<int Function()> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CriticalEventOverlay(
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => taps++,
                child: const Text('Work underneath'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return () => taps;
  }

  /// Tears the tree down so the alert layer's escalation timers are cancelled
  /// before the binding checks for pending timers.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    // Outstanding critical work rings the device on a repeating timer that
    // deliberately outlives any one screen — in the app it stops at sign-out.
    // Stop it here so the binding's pending-timer check sees a clean slate.
    SosRingService.instance.stop();
  }

  testWidgets(
    'an outstanding alert arrives as a notification, not a takeover',
    (tester) async {
      seed([alert('a1')]);
      await pumpPage(tester);

      expect(find.text('Patient p1'), findsOneWidget);
      expect(find.text('Blood Pressure critical'), findsOneWidget);

      // The old surface was showGeneralDialog with a dimmed barrier. Nothing
      // may be pushed over the page any more.
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
      expect(
        find.text('Work underneath'),
        findsOneWidget,
        reason: 'the page the user signed in to reach stays visible',
      );

      await unmount(tester);
    },
  );

  testWidgets('the page underneath stays usable while an alert is showing', (
    tester,
  ) async {
    seed([alert('a1')]);
    final taps = await pumpPage(tester);

    await tester.tap(find.text('Work underneath'));
    await tester.pump();

    expect(
      taps(),
      1,
      reason: 'an alert must never block the work it is interrupting',
    );

    await unmount(tester);
  });

  testWidgets('the notification is a tap target', (tester) async {
    seed([alert('a1')]);
    await pumpPage(tester);

    expect(
      find.ancestor(
        of: find.text('Blood Pressure critical'),
        matching: find.byType(InkWell),
      ),
      findsWidgets,
      reason: 'the whole strip opens the queue, not just a small control',
    );

    await unmount(tester);
  });

  testWidgets('dismissing defers the alert without attending to it', (
    tester,
  ) async {
    seed([alert('a1')]);
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Remind me in 5 minutes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Blood Pressure critical'), findsNothing);
    expect(
      AlertCenter.instance.unattendedCount,
      1,
      reason: 'dismissing is deferring — the alert is still someone\'s job',
    );
    expect(AlertCenter.instance.snoozedUntilFor('alert:a1'), isNotNull);

    await unmount(tester);
  });

  testWidgets('the whole queue arrives as one line', (tester) async {
    seed([for (var i = 0; i < 5; i++) alert('a$i')]);
    await pumpPage(tester);

    // One strip, not a card per alert and a chip underneath: five alerts must
    // cost the page a line, not a third of the screen.
    expect(find.text('Patient p1'), findsOneWidget);
    expect(
      find.text('+4'),
      findsOneWidget,
      reason: 'the rest are counted on the same line, not floated below it',
    );

    await unmount(tester);
  });

  /// Mounts the page with the dashboard's inline queue card on it.
  Future<void> pumpPageWithInlineQueue(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const CriticalEventOverlay(
          child: Scaffold(
            body: SingleChildScrollView(child: UrgentAlertsCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the banner stands down where the page already shows the queue', (
    tester,
  ) async {
    seed([alert('a1')]);
    await pumpPageWithInlineQueue(tester);

    // The dashboard card and a banner floating the same alert over it were
    // two pictures of one queue on one screen, each with its own count and
    // one covering the other. Only the page's own surface may speak.
    expect(
      find.byTooltip('Remind me in 5 minutes'),
      findsNothing,
      reason: 'the floating strip must not duplicate the inline card',
    );
    expect(
      find.byTooltip('Show all 1'),
      findsOneWidget,
      reason: 'the page speaks for it, as its own notification line',
    );
    expect(
      AlertCenter.instance.surfaceCountFor('alert:a1'),
      0,
      reason: 'nothing may climb the escalation ladder while unshown',
    );

    await unmount(tester);
  });

  testWidgets('an alert that lands while you are on that page still flies', (
    tester,
  ) async {
    // One alert instance, kept across both seeds — an alert already on the
    // page does not get a new timestamp just because the session refreshed.
    final standing = alert('a1');

    seed([standing]);
    await pumpPageWithInlineQueue(tester);

    // Standing work stays on the page.
    expect(find.byTooltip('Remind me in 5 minutes'), findsNothing);

    // Suppressing the layer outright because a page happened to list the
    // queue also swallowed this: the emergency raised while someone was
    // reading that very page, which is the one case a heads-up exists for.
    seed([standing, alert('a2', severity: RiskLevel.critical)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.byTooltip('Remind me in 5 minutes'),
      findsOneWidget,
      reason: 'an arrival is a notification, not a row someone might scroll to',
    );
    expect(
      AlertCenter.instance.surfaceCountFor('alert:a1'),
      0,
      reason: 'the one already listed on the page did not also fly',
    );
    expect(AlertCenter.instance.surfaceCountFor('alert:a2'), 1);

    await unmount(tester);
  });

  testWidgets('the queue waits a beat before interrupting again', (
    tester,
  ) async {
    seed([alert('a1')]);
    await pumpPage(tester);
    expect(find.text('Blood Pressure critical'), findsOneWidget);

    // Closing a popup used to hand the next item straight back as another
    // popup, covering the result of what was just done.
    AlertCenter.instance.holdBanners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Blood Pressure critical'), findsNothing);

    // Holding is not dropping. The item is still outstanding, still unowned,
    // and still on every other surface — it has simply stopped re-covering
    // the person already dealing with it. (When it returns is the escalation
    // ladder's business, and that runs on the wall clock, which a widget test
    // cannot wind forward.)
    expect(AlertCenter.instance.unattendedCount, 1);
    expect(AlertCenter.instance.openQueue.single.id, 'alert:a1');

    await unmount(tester);
  });

  testWidgets('a patient never sees the staff alert layer', (tester) async {
    AuthState.instance.signIn(
      AppUser(
        id: 'u2',
        uniqueId: 'MCR-000002',
        firstName: 'Test',
        lastName: 'Patient',
        email: 'patient@example.com',
        role: UserRole.patient,
      ),
    );
    seed([alert('a1')]);
    await pumpPage(tester);

    expect(find.text('Patient p1'), findsNothing);

    await unmount(tester);
  });
}

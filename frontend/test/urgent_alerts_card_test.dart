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
import 'package:mcare/shared/widgets/glass_card.dart';

/// The dashboard's standing picture of the urgent queue.
///
/// It used to flash: the admin sync emptied every bucket *before* fetching, so
/// for the length of the round trip the app genuinely held no alerts and the
/// card rendered "No urgent items outstanding" over six live ones — two of
/// them emergencies — then took it back when the payload landed. On an active
/// SOS the poll runs every eight seconds, so it flashed that often.
///
/// These pin that the card never claims a clear queue it cannot stand behind,
/// and that its height does not move as the queue changes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StaffPatient patient(String id, String name) => StaffPatient(
    id: id,
    name: name,
    age: 44,
    sex: 'F',
    condition: 'Hypertension',
    risk: RiskLevel.critical,
    lastReading: DateTime.now(),
    assignedDoctor: 'Dr. Test',
  );

  StaffAlert alert(String id, {String name = 'Wangari Njeri'}) => StaffAlert(
    id: id,
    patientId: 'p1',
    patientName: name,
    vital: VitalKey.bloodPressure,
    value: '172/108',
    severity: RiskLevel.critical,
    createdAt: DateTime.now(),
  );

  void seed(List<StaffAlert> alerts) {
    StaffState.instance.seedFromApi(
      patients: [patient('p1', 'Wangari Njeri')],
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
        firstName: 'Nia',
        lastName: 'Chebet',
        email: 'admin@mcare.health',
        role: UserRole.admin,
      ),
    );
  });

  tearDown(() {
    AlertCenter.instance.reset();
    SosRingService.instance.stop();
    StaffState.instance.clear();
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    List<QuietNote> quiet = const [],
  }) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: UrgentAlertsCard(quiet: quiet)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Waits out one turn of the strip, and the cross-fade into the next.
  Future<void> nextTurn(WidgetTester tester) async {
    await tester.pump(UrgentAlertsCard.turn);
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Opens the board behind the notification line.
  Future<void> expand(WidgetTester tester, int total) async {
    await tester.tap(find.byTooltip('Show all $total'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    SosRingService.instance.stop();
  }

  testWidgets('a refresh never blanks the queue it is refreshing', (
    tester,
  ) async {
    seed([for (var i = 0; i < 6; i++) alert('a$i')]);
    await pumpCard(tester);

    expect(find.byTooltip('Show all 6'), findsOneWidget);
    expect(find.text('Wangari Njeri'), findsOneWidget);

    // A refresh starts and, mid-flight, something else rebuilds the card.
    StaffState.instance.beginSync();
    seed(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.text('Nothing urgent outstanding'),
      findsNothing,
      reason: 'a queue being refreshed is not a queue that is clear',
    );
    expect(find.byTooltip('Show all 6'), findsOneWidget);

    // The refresh lands, and it really is clear this time.
    StaffState.instance.endSync();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Nothing urgent outstanding'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a settled empty queue still reads as all clear', (tester) async {
    seed(const []);
    await pumpCard(tester);

    expect(find.text('Nothing urgent outstanding'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the opened board holds its height as the queue grows', (
    tester,
  ) async {
    seed([for (var i = 0; i < 4; i++) alert('a$i')]);
    await pumpCard(tester);
    await expand(tester, 4);
    final atFour = tester.getSize(find.byType(UrgentAlertsCard)).height;

    // Two more arrive. They must be reachable by scrolling the list, not by
    // pushing the rest of the dashboard down the page.
    seed([for (var i = 0; i < 6; i++) alert('a$i')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('6 unattended'), findsOneWidget);
    expect(
      tester.getSize(find.byType(UrgentAlertsCard)).height,
      atFour,
      reason: 'the dashboard must not move under the operator as alerts land',
    );
    expect(find.byType(Scrollbar), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('every queued alert is reachable by scrolling', (tester) async {
    seed([for (var i = 0; i < 6; i++) alert('a$i')]);
    await pumpCard(tester);
    await expand(tester, 6);

    final list = find.descendant(
      of: find.byType(UrgentAlertsCard),
      matching: find.byType(ListView),
    );
    expect(list, findsOneWidget);
    expect(
      tester.widget<ListView>(list).semanticChildCount,
      6,
      reason: 'nothing is hidden behind a "+2 more" the operator cannot see',
    );

    await unmount(tester);
  });

  // -------------------------------------------------------- as a notification

  testWidgets('collapsed, it is one line that names the worst item', (
    tester,
  ) async {
    seed([for (var i = 0; i < 6; i++) alert('a$i')]);
    await pumpCard(tester);

    // Who, what, and how many behind it — the four things a phone
    // notification says, and nothing else.
    expect(find.text('Wangari Njeri'), findsOneWidget);
    expect(find.textContaining('Blood Pressure critical'), findsOneWidget);
    expect(
      find.text('6'),
      findsOneWidget,
      reason: 'the count sits on the icon',
    );
    expect(find.text('+5'), findsOneWidget);

    // The board it replaced is not on the page until someone asks for it.
    expect(find.textContaining('Work through'), findsNothing);
    expect(find.text('Open all alerts'), findsNothing);

    await unmount(tester);
  });

  testWidgets('the notification costs the dashboard one line, whatever the '
      'queue holds', (tester) async {
    seed([alert('a0')]);
    await pumpCard(tester);
    final atOne = tester.getSize(find.byType(UrgentAlertsCard)).height;

    expect(
      atOne,
      lessThan(90),
      reason:
          'a third of the screen for a standing queue is what this '
          'replaced',
    );

    seed([for (var i = 0; i < 6; i++) alert('a$i')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getSize(find.byType(UrgentAlertsCard)).height, atOne);

    await unmount(tester);
  });

  testWidgets('it is a line on the page, not a card on it', (tester) async {
    seed([for (var i = 0; i < 6; i++) alert('a$i')]);
    await pumpCard(tester);

    expect(
      find.descendant(
        of: find.byType(UrgentAlertsCard),
        matching: find.byType(GlassCard),
      ),
      findsNothing,
      reason: 'a notification is not a panel',
    );

    // The tap target starts at the page edge — there is no card inset to
    // give it away, so the line itself has to be the thing you hit.
    final target = find
        .descendant(
          of: find.byType(UrgentAlertsCard),
          matching: find.byType(InkWell),
        )
        .first;
    expect(tester.getTopLeft(target).dx, 0);
    expect(
      tester.getBottomRight(target).dx,
      greaterThan(360),
      reason: 'it runs the width of the page, less the chevron',
    );

    // What the border used to do, a rule does instead.
    expect(
      find.descendant(
        of: find.byType(UrgentAlertsCard),
        matching: find.byType(Divider),
      ),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('it expands to the full board and folds back', (tester) async {
    seed([for (var i = 0; i < 6; i++) alert('a$i')]);
    await pumpCard(tester);
    final collapsed = tester.getSize(find.byType(UrgentAlertsCard)).height;

    await expand(tester, 6);
    expect(find.textContaining('Work through 6 unattended'), findsOneWidget);
    expect(find.text('Open all alerts'), findsOneWidget);
    expect(
      tester.getSize(find.byType(UrgentAlertsCard)).height,
      greaterThan(collapsed),
    );

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Work through'), findsNothing);
    expect(tester.getSize(find.byType(UrgentAlertsCard)).height, collapsed);

    await unmount(tester);
  });

  // ------------------------------------------------------------ taking turns

  testWidgets('the strip takes turns, so the last alert is seen too', (
    tester,
  ) async {
    seed([
      alert('a0', name: 'Wangari Njeri'),
      alert('a1', name: 'Amara Okonkwo'),
      alert('a2', name: 'Brian Otieno'),
    ]);
    await pumpCard(tester);

    // One at a time — a strip showing three names at once is a list again.
    expect(find.text('Wangari Njeri'), findsOneWidget);
    expect(find.text('Amara Okonkwo'), findsNothing);

    await nextTurn(tester);
    expect(find.text('Amara Okonkwo'), findsOneWidget);
    expect(find.text('Wangari Njeri'), findsNothing);

    // The third one is reached without anybody opening anything, which is the
    // whole reason the line rotates.
    await nextTurn(tester);
    expect(find.text('Brian Otieno'), findsOneWidget);

    await nextTurn(tester);
    expect(find.text('Wangari Njeri'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('turns stop while the board is open', (tester) async {
    seed([
      alert('a0', name: 'Wangari Njeri'),
      alert('a1', name: 'Amara Okonkwo'),
    ]);
    await pumpCard(tester);
    await expand(tester, 2);

    // Expanded, every item is already on screen; rotating the header as well
    // would be the page moving under someone who asked it to hold still.
    final header = find.descendant(
      of: find.byType(UrgentAlertsCard),
      matching: find.text('Wangari Njeri'),
    );
    expect(header, findsWidgets);
    await nextTurn(tester);
    expect(header, findsWidgets);

    await unmount(tester);
  });

  // ------------------------------------------------- when nothing is urgent

  testWidgets('a clear queue hands the line to the page own work', (
    tester,
  ) async {
    seed(const []);
    await pumpCard(
      tester,
      quiet: const [
        QuietNote(
          title: 'Care requests',
          detail: 'Waiting on you',
          icon: Icons.assignment_outlined,
          accent: Color(0xFF3B82F6),
          count: 5,
        ),
      ],
    );

    // It still says the queue is clear — once.
    expect(find.text('Nothing urgent outstanding'), findsOneWidget);

    // And then gets on with what the page actually has waiting, rather than
    // holding the top of the dashboard to report an absence.
    await nextTurn(tester);
    expect(find.text('Care requests'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);

    // The dropdown remains useful while the queue is clear: it opens the
    // bounded overview behind the rotating line instead of disappearing.
    expect(find.byTooltip('Show dashboard overview'), findsOneWidget);
    await tester.tap(find.byTooltip('Show dashboard overview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip('Collapse'), findsOneWidget);
    expect(find.text('Nothing urgent outstanding'), findsWidgets);
    expect(find.text('Care requests'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('quiet statistics rotate in the same footprint without a card', (
    tester,
  ) async {
    seed(const []);
    await pumpCard(
      tester,
      quiet: const [
        QuietNote(
          title: 'Operations overview',
          detail: '3 open work items in your scope',
          icon: Icons.insights_rounded,
          accent: Color(0xFF6750A4),
        ),
        QuietNote(
          title: 'People on mCare',
          detail: '18 active patients · 26 registered users',
          icon: Icons.groups_2_rounded,
          accent: Color(0xFF3B82F6),
        ),
      ],
    );
    final height = tester.getSize(find.byType(UrgentAlertsCard)).height;

    expect(find.text('1/3'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(UrgentAlertsCard),
        matching: find.byType(GlassCard),
      ),
      findsNothing,
    );

    await nextTurn(tester);
    expect(find.text('Operations overview'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(tester.getSize(find.byType(UrgentAlertsCard)).height, height);

    await nextTurn(tester);
    expect(find.text('People on mCare'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);
    expect(tester.getSize(find.byType(UrgentAlertsCard)).height, height);

    await unmount(tester);
  });

  testWidgets('a clear queue with nothing waiting still costs one line', (
    tester,
  ) async {
    seed(const []);
    await pumpCard(tester);

    // The strip never renders nothing: a blank where the queue lives reads as
    // a broken dashboard, not a quiet one. It is one line, and on a real
    // dashboard the page's own work takes the turns after it.
    expect(find.text('Nothing urgent outstanding'), findsOneWidget);
    expect(tester.getSize(find.byType(UrgentAlertsCard)).height, lessThan(90));

    await unmount(tester);
  });
}

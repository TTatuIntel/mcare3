import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/shared/alerts/alert_center.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/services/sos_ring_service.dart';
import 'package:mcare/shared/sos/sos_responder_sheet.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/critical_event_overlay.dart';

/// Working an emergency is a session, not a single button. These pin that the
/// responder can stay in it and see it through: the queue goes quiet while
/// they work, ownership does not eject them, and once the event is closed
/// nothing on the page pretends to still be actionable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StaffPatient patient() => StaffPatient(
    id: 'p1',
    name: 'Amara Okonkwo',
    age: 54,
    sex: 'F',
    condition: 'Hypertension',
    risk: RiskLevel.critical,
    lastReading: DateTime.now(),
    assignedDoctor: 'Dr. Sarah Adeyemi',
  );

  StaffPatientSos sos({String status = 'active'}) => StaffPatientSos(
    id: 's1',
    patientId: 'p1',
    patientName: 'Amara Okonkwo',
    kind: 'medical',
    status: status,
    triggeredAt: DateTime.now(),
    locationLabel: 'Nairobi, Westlands',
  );

  void seed(List<StaffPatientSos> events) {
    StaffState.instance.seedFromApi(
      patients: [patient()],
      alerts: const [],
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      sosEvents: events,
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
    ApiClient.instance.setTransportForTesting(
      MockClient(
        (req) async => http.Response(
          req.method == 'GET' ? '{"success":false}' : '{"success":true}',
          req.method == 'GET' ? 503 : 200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    AlertCenter.instance.reset();
    SosRingService.instance.stop();
    StaffState.instance.clear();
  });

  /// Mounts the alert layer over a page, then opens the responder sheet the
  /// way the app does.
  Future<void> pumpResponder(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CriticalEventOverlay(
          child: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => SosResponderSheet.show(
                    ctx,
                    event: StaffState.instance.patientSos.first,
                    role: UserRole.admin,
                  ),
                  child: const Text('Respond now'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('Respond now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    SosRingService.instance.stop();
  }

  testWidgets('the queue goes quiet while the responder is working', (
    tester,
  ) async {
    seed([sos()]);
    await pumpResponder(tester);

    // The banner is there before the workflow starts. The strip's own defer
    // control is what identifies it — the words it shows are the emergency's,
    // and the sheet shows those too.
    expect(find.byTooltip('Remind me in 5 minutes'), findsOneWidget);

    await openSheet(tester);

    expect(
      find.byTooltip('Remind me in 5 minutes'),
      findsNothing,
      reason:
          'a card for the emergency being worked, on top of the controls '
          'used to work it, is noise at the worst possible moment',
    );
    expect(AlertCenter.instance.isPresenting, isTrue);

    await settle(tester);
  });

  testWidgets('the banners come back when the responder leaves', (
    tester,
  ) async {
    seed([sos()]);
    await pumpResponder(tester);
    await openSheet(tester);

    Navigator.of(tester.element(find.text('Take ownership'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // A sheet now hands control back only once its exit transition has
    // finished, so the work it triggered lands a frame later.
    await tester.pump(const Duration(milliseconds: 600));

    expect(AlertCenter.instance.isPresenting, isFalse);
    expect(
      find.byTooltip('Remind me in 5 minutes'),
      findsOneWidget,
      reason: 'an emergency left unworked has to keep asking',
    );

    await settle(tester);
  });

  testWidgets('taking ownership keeps the responder in the workflow', (
    tester,
  ) async {
    seed([sos()]);
    await pumpResponder(tester);
    await openSheet(tester);

    expect(find.text('Raised'), findsOneWidget);
    expect(find.text('Take ownership'), findsOneWidget);

    await tester.tap(find.text('Take ownership'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      StaffState.instance.patientSos.single.status,
      'acknowledged',
      reason: 'ownership must actually persist',
    );
    expect(
      find.text('Resolve the emergency'),
      findsOneWidget,
      reason:
          'ownership is the middle of the response, not the end — the '
          'responder stays here to finish it',
    );
    expect(
      find.text('Take ownership'),
      findsNothing,
      reason: 'an owned emergency no longer offers to be owned',
    );
    expect(
      AlertCenter.instance.popQueue,
      isEmpty,
      reason: 'an owned emergency stops interrupting',
    );

    await settle(tester);
  });

  testWidgets('a closed emergency leaves nothing pretending to be actionable', (
    tester,
  ) async {
    seed([sos()]);
    await pumpResponder(tester);
    await openSheet(tester);

    // Someone else closes it while this sheet is open.
    seed(const []);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('has been closed'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);

    final resolve = tester.widget<InkWell>(
      find
          .ancestor(
            of: find.text('Resolve the emergency'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(
      resolve.onTap,
      isNull,
      reason: 'controls must go flat, not fail against a row that is gone',
    );

    await settle(tester);
  });
}

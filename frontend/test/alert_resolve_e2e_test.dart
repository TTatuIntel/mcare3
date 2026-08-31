import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/shared/alerts/alert_center.dart';
import 'package:mcare/shared/alerts/alert_return_point.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/services/sos_ring_service.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/app_button.dart';
import 'package:mcare/shared/widgets/critical_event_overlay.dart';

/// The whole path an admin actually walks: a notification arrives, they tap
/// it, they work it, and it is gone from every surface that counted it.
///
/// This is pinned end to end because the individual pieces each passed while
/// the journey did not — a stale "already presenting" flag made every tap a
/// silent no-op, and a return that popped an unmatched route left a blank
/// window. Neither shows up in a unit test of either piece.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StaffPatient patient(String id, String name) => StaffPatient(
    id: id,
    name: name,
    age: 62,
    sex: 'F',
    condition: 'Hypertension',
    risk: RiskLevel.critical,
    lastReading: DateTime.now(),
    assignedDoctor: 'Dr. Sarah Adeyemi',
  );

  StaffAlert alert(String id) => StaffAlert(
    id: id,
    patientId: 'p1',
    patientName: 'Wangari Njeri',
    vital: VitalKey.bloodPressure,
    value: '190/120',
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
    AlertReturnPoint.clear();
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
    AlertReturnPoint.clear();
    AlertCenter.instance.reset();
    SosRingService.instance.stop();
    StaffState.instance.clear();
    NotificationState.instance.seed(const []);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        initialRoute: RouteNames.adminWork,
        routes: {
          RouteNames.adminWork: (_) => const CriticalEventOverlay(
            currentRoute: RouteNames.adminWork,
            child: Scaffold(body: Center(child: Text('Work queue'))),
          ),
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    SosRingService.instance.stop();
  }

  testWidgets(
    'an admin can work a critical alert from the notification to gone',
    (tester) async {
      seed([alert('a1')]);
      await pumpApp(tester);

      // 1. It arrives as one line, over a page that still works.
      expect(find.text('Blood Pressure critical'), findsOneWidget);
      expect(find.text('Wangari Njeri'), findsOneWidget);
      expect(find.text('Work queue'), findsOneWidget);

      // 2. Tapping it opens the alert with its actions.
      await tester.tap(find.text('Blood Pressure critical'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // 3. Both routes are offered straight away. Staff who already know the
      //    outcome resolve on the spot; the resolve sheet still demands an
      //    action and a note, so nothing is recorded unclaimed. Acknowledging
      //    first stays available and must not remove the resolve route.
      expect(find.text('Acknowledge'), findsOneWidget);
      expect(find.text('Resolve'), findsOneWidget);
      expect(
        find.textContaining('or resolve now with a reason'),
        findsOneWidget,
      );
      await tester.tap(find.text('Acknowledge'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Resolve'), findsOneWidget);

      // 4. Resolving documents the clinical outcome.
      await tester.tap(find.text('Resolve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Resolve alert'), findsWidgets);

      await tester.tap(find.text('Patient contacted').first);
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Resolve alert'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      // 4. It is gone from the queue, the inbox and the badge.
      expect(
        StaffState.instance.alerts.single.resolved,
        isTrue,
        reason: 'the alert itself has to be closed, not just hidden',
      );
      expect(AlertCenter.instance.openQueue, isEmpty);
      expect(
        NotificationState.instance.items.any((n) => n.id == 'staff_alert_a1'),
        isFalse,
      );

      await settle(tester);
    },
  );

  testWidgets('a second alert is still workable after the first', (
    tester,
  ) async {
    // This is the regression that made alerts unusable in practice: the first
    // one opened, and every one after it did nothing at all. Two causes, both
    // invisible to a unit test — the visible list was mutated in place so the
    // card was painted from a stale frame, and the layer sat inside the page
    // route, whose pointer handling is gated while a dialog above it closes.
    seed([alert('a1'), alert('a2')]);
    await pumpApp(tester);

    // One line for the pair: the worst named, the rest counted.
    expect(find.text('Blood Pressure critical'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);

    // Tapping it opens the queue — not one alert, then nothing.
    await tester.tap(find.text('Blood Pressure critical'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    for (var round = 0; round < 2; round++) {
      expect(
        find.text('Acknowledge'),
        findsOneWidget,
        reason: 'round $round: the alert must be open and workable',
      );
      expect(AlertCenter.instance.isPresenting, isTrue);

      // Defer it; the queue moves to the next one inside the same popup
      // rather than closing and re-covering the page with a new one.
      await tester.tap(find.text('5m reminder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    expect(
      AlertCenter.instance.isPresenting,
      isFalse,
      reason: 'an exhausted queue must release the popup',
    );
    expect(
      find.text('Work queue'),
      findsOneWidget,
      reason: 'and hand the operator back real content, never a blank frame',
    );

    await settle(tester);
  });

  testWidgets('an alert can be resolved with a reason, unacknowledged', (
    tester,
  ) async {
    seed([alert('a1')]);
    await pumpApp(tester);

    await tester.tap(find.text('Blood Pressure critical'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Straight to the outcome, with no acknowledgement first. Staff who
    // already handled the patient were previously forced through a tap that
    // recorded nothing.
    await tester.tap(find.text('Resolve'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Resolve alert'), findsWidgets);

    // The reason is not optional — an outcome with no action is refused.
    await tester.tap(find.widgetWithText(AppButton, 'Resolve alert'));
    await tester.pump();
    expect(
      find.textContaining('Select the action you took'),
      findsOneWidget,
      reason: 'resolving without a reason must not be recordable',
    );
    expect(StaffState.instance.alerts.single.resolved, isFalse);

    await tester.tap(find.text('Patient contacted').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Resolve alert'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final resolved = StaffState.instance.alerts.single;
    expect(resolved.resolved, isTrue);
    expect(resolved.resolutionAction, 'patient_contacted');
    expect(
      resolved.resolutionNote,
      isNotEmpty,
      reason: 'the chart needs the reason, not just the fact it closed',
    );
    expect(
      resolved.acknowledged,
      isTrue,
      reason: 'resolving takes the alert on in the same step',
    );
    expect(AlertCenter.instance.openQueue, isEmpty);

    await settle(tester);
  });

  testWidgets('the page underneath is never left blank', (tester) async {
    seed([alert('a1')]);
    await pumpApp(tester);

    await tester.tap(find.text('Blood Pressure critical'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('5m reminder').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Work queue'),
      findsOneWidget,
      reason: 'closing an alert returns the operator to real content',
    );

    await settle(tester);
  });
}

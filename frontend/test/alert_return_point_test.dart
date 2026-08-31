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
import 'package:mcare/shared/sos/staff_sos_hub_view.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// Responding to an emergency is the one flow that moves the operator to
/// another page. Before this, closing the emergency left them wherever the
/// flow had walked them, with no statement of what had finished — so the
/// question "am I done, and where am I?" had no answer on screen.
///
/// A workflow now has a recorded start and a stated ending, and the operator
/// picks the ending. Nothing navigates on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StaffPatient patient(String id, String name) => StaffPatient(
    id: id,
    name: name,
    age: 40,
    sex: 'F',
    condition: 'Hypertension',
    risk: RiskLevel.normal,
    lastReading: DateTime.now(),
    assignedDoctor: 'Dr. Test',
  );

  StaffPatientSos sos(String id, String patientId) => StaffPatientSos(
    id: id,
    patientId: patientId,
    patientName: 'Wangari Njeri',
    kind: 'medical',
    status: 'active',
    triggeredAt: DateTime.now(),
  );

  void seed(List<StaffPatientSos> events) {
    StaffState.instance.seedFromApi(
      patients: [patient('p1', 'Wangari Njeri')],
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
    // Writes succeed; reads fail so the hub's refresh cannot wipe the seeded
    // fixtures with an empty session payload.
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
  });

  group('the return point itself', () {
    testWidgets('records the page the workflow started from', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: RouteNames.adminDashboard,
          routes: {
            RouteNames.adminDashboard: (ctx) => Builder(
              builder: (ctx) {
                AlertReturnPoint.remember(ctx);
                return const SizedBox();
              },
            ),
          },
        ),
      );
      await tester.pump();

      expect(AlertReturnPoint.current?.route, RouteNames.adminDashboard);
      expect(AlertReturnPoint.current?.label, 'Dashboard');
    });

    testWidgets('refuses to record a page the workflow itself ends on', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: RouteNames.adminSos,
          routes: {
            RouteNames.adminSos: (ctx) => Builder(
              builder: (ctx) {
                AlertReturnPoint.remember(ctx);
                return const SizedBox();
              },
            ),
          },
        ),
      );
      await tester.pump();

      expect(
        AlertReturnPoint.current,
        isNull,
        reason: 'returning to the page you are already on is not a return',
      );
    });

    test('names every hub an operator can start from', () {
      expect(AlertReturnPoint.labelFor(RouteNames.adminWork), 'Work');
      expect(AlertReturnPoint.labelFor(RouteNames.adminPatients), 'Patients');
      expect(AlertReturnPoint.labelFor(RouteNames.doctorInbox), 'Action inbox');
      expect(AlertReturnPoint.labelFor('/some/unmapped'), 'where you were');
    });
  });

  group('ending an emergency', () {
    Future<void> pumpFlow(WidgetTester tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          initialRoute: RouteNames.adminDashboard,
          routes: {
            RouteNames.adminDashboard: (_) =>
                const Scaffold(body: Center(child: Text('Admin dashboard'))),
            RouteNames.adminSos: (_) => const StaffSosHubView(),
          },
        ),
      );
      await tester.pump();

      // Start the workflow the way an alert does: record the origin, then go.
      final ctx = tester.element(find.text('Admin dashboard'));
      AlertReturnPoint.remember(ctx);
      Navigator.of(ctx).pushNamed(RouteNames.adminSos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    Future<void> resolveFirst(WidgetTester tester) async {
      // Closing is only offered to whoever picked the emergency up, so the
      // workflow starts by taking it on — which confirms like any other
      // status change.
      await tester.tap(find.text('Acknowledge — en route').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirm').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Resolve').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirm').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> unmount(WidgetTester tester) async {
      // Success toasts own a 3.5s timer and a fade-out; let them expire or the
      // binding sees them as timers outliving the tree.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      SosRingService.instance.stop();
    }

    testWidgets('states what finished and offers both endings', (tester) async {
      seed([sos('s1', 'p1')]);
      await pumpFlow(tester);
      await resolveFirst(tester);

      expect(find.text('Emergency closed for Wangari Njeri'), findsOneWidget);
      expect(find.text('Back to Dashboard'), findsOneWidget);
      expect(find.text('Stay here'), findsOneWidget);
      expect(
        find.text('Admin dashboard'),
        findsNothing,
        reason: 'the workflow must not navigate on its own',
      );

      await unmount(tester);
    });

    testWidgets('taking the return goes back to where the work started', (
      tester,
    ) async {
      seed([sos('s1', 'p1')]);
      await pumpFlow(tester);
      await resolveFirst(tester);

      await tester.tap(find.text('Back to Dashboard'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Admin dashboard'), findsOneWidget);
      expect(
        AlertReturnPoint.current,
        isNull,
        reason: 'a spent return point must not fire again later',
      );

      await unmount(tester);
    });

    testWidgets('staying keeps the operator on the queue', (tester) async {
      seed([sos('s1', 'p1')]);
      await pumpFlow(tester);
      await resolveFirst(tester);

      await tester.tap(find.text('Stay here'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Emergency closed for Wangari Njeri'), findsNothing);
      expect(find.text('Admin dashboard'), findsNothing);
      expect(find.text('Emergency SOS'), findsWidgets);

      await unmount(tester);
    });
  });
}

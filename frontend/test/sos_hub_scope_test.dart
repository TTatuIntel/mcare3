import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/alerts/alert_center.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/services/sos_ring_service.dart';
import 'package:mcare/shared/sos/staff_sos_hub_view.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// Opening the SOS hub from an alert scopes it to one patient. That scope used
/// to be invisible and permanent: the hero counted every active emergency on
/// the platform while the list below counted only the scoped patient's, so
/// closing the event you arrived for left a page reading "1 active SOS" above
/// "No active SOS". These pin that the two never disagree again.
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
    patientName: 'Patient $patientId',
    kind: 'medical',
    status: 'active',
    triggeredAt: DateTime.now(),
  );

  void seed(List<StaffPatientSos> events) {
    StaffState.instance.seedFromApi(
      patients: [patient('p1', 'Wangari Njeri'), patient('p2', 'Brian Otieno')],
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
  });

  tearDown(() {
    AlertCenter.instance.reset();
    SosRingService.instance.stop();
    StaffState.instance.clear();
  });

  Future<void> pumpHub(WidgetTester tester, {String? patientId}) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: StaffSosHubView(initialPatientId: patientId),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    SosRingService.instance.stop();
  }

  testWidgets('the hero never claims more emergencies than the list shows', (
    tester,
  ) async {
    // Two active emergencies; the hub is scoped to the one the responder
    // navigated in for. The other patient's event must not be counted here.
    seed([sos('s1', 'p1'), sos('s2', 'p2')]);
    await pumpHub(tester, patientId: 'p1');

    expect(find.text('1 active SOS'), findsOneWidget);
    expect(find.text('2 active SOS'), findsNothing);
    expect(find.text('No active SOS'), findsNothing);

    await unmount(tester);
  });

  testWidgets('a scoped hub says so and offers the way out', (tester) async {
    seed([sos('s1', 'p1'), sos('s2', 'p2')]);
    await pumpHub(tester, patientId: 'p1');

    expect(find.text('Showing Wangari Njeri only'), findsOneWidget);
    expect(
      find.text('Show all (1 more)'),
      findsOneWidget,
      reason: 'the responder must be able to reach the rest of the queue',
    );

    await unmount(tester);
  });

  testWidgets('showing all widens the list to every active emergency', (
    tester,
  ) async {
    seed([sos('s1', 'p1'), sos('s2', 'p2')]);
    await pumpHub(tester, patientId: 'p1');

    await tester.tap(find.text('Show all (1 more)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('2 active SOS'), findsOneWidget);
    expect(find.textContaining('Showing '), findsNothing);

    await unmount(tester);
  });

  testWidgets('an empty scope explains itself instead of reading as broken', (
    tester,
  ) async {
    // The scoped patient's emergency is already closed; another is waiting.
    seed([sos('s2', 'p2')]);
    await pumpHub(tester, patientId: 'p1');

    expect(find.text('Nothing left for this patient'), findsOneWidget);
    expect(find.textContaining('1 other patient is still waiting'), findsOneWidget);
    expect(find.text('Show all active SOS'), findsOneWidget);
    expect(
      find.text('1 active SOS'),
      findsNothing,
      reason: 'the old bug: a hero counting work the empty list denied',
    );

    await unmount(tester);
  });

  testWidgets('an unscoped hub lists every active emergency', (tester) async {
    seed([sos('s1', 'p1'), sos('s2', 'p2')]);
    await pumpHub(tester);

    expect(find.text('2 active SOS'), findsOneWidget);
    expect(find.textContaining('Showing '), findsNothing);

    await unmount(tester);
  });
}

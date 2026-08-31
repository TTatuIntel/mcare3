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

/// The dashboard band is a fixed slice of the page whether the queue holds one
/// alert or twenty, so the only way it earns that space is by saying more in
/// it. This pins what it says — the reading, who owns it, and what is behind
/// it — and that saying it did not cost the page any height.
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

  StaffAlert alert(
    String id, {
    String value = '172/108',
    VitalKey vital = VitalKey.bloodPressure,
    RiskLevel severity = RiskLevel.critical,
    bool acknowledged = false,
  }) => StaffAlert(
    id: id,
    patientId: 'p1',
    patientName: 'Wangari Njeri',
    vital: vital,
    value: value,
    severity: severity,
    createdAt: DateTime.now(),
    acknowledged: acknowledged,
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

  Future<void> pumpCard(WidgetTester tester, {double width = 430}) async {
    tester.view.physicalSize = Size(width, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: UrgentAlertsCard()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    SosRingService.instance.stop();
  }

  testWidgets('the reading that raised the alert is on the line', (
    tester,
  ) async {
    seed([alert('a0')]);
    await pumpCard(tester);

    // It was already loaded and only visible once someone opened the queue.
    expect(find.text('172/108 mmHg'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('an unowned alert says so, and an owned one says that instead', (
    tester,
  ) async {
    seed([alert('a0')]);
    await pumpCard(tester);
    expect(find.text('Not yet owned'), findsOneWidget);
    expect(find.text('Owned'), findsNothing);

    seed([alert('a0', acknowledged: true)]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Owned'), findsOneWidget);
    expect(find.text('Not yet owned'), findsNothing);

    await unmount(tester);
  });

  testWidgets('the line states what the queue behind it is made of', (
    tester,
  ) async {
    seed([
      alert('a0'),
      alert('a1'),
      alert('a2', severity: RiskLevel.warning, vital: VitalKey.heartRate),
    ]);
    await pumpCard(tester);

    expect(
      find.textContaining('2 critical'),
      findsOneWidget,
      reason: 'the severity mix is only otherwise visible once expanded',
    );
    expect(find.textContaining('1 warning'), findsOneWidget);
    expect(find.textContaining('3 not yet owned'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the denser line still costs the page one band', (tester) async {
    seed([alert('a0')]);
    await pumpCard(tester);
    final atOne = tester.getSize(find.byType(UrgentAlertsCard)).height;

    // 64 for the line — its own long-standing minimum — plus the 17 of the
    // rule under it. Everything the line gained fits inside that floor, so
    // the band is the exact height it was before it started saying more.
    expect(atOne, lessThanOrEqualTo(81));

    seed([for (var i = 0; i < 8; i++) alert('a$i')]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.getSize(find.byType(UrgentAlertsCard)).height,
      atOne,
      reason: 'a queue that grows must not push the dashboard down',
    );

    await unmount(tester);
  });

  testWidgets('a long emergency location cannot overflow the line', (
    tester,
  ) async {
    StaffState.instance.seedFromApi(
      patients: [patient('p1', 'Wangari Njeri')],
      alerts: const [],
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      sosEvents: [
        StaffPatientSos(
          id: 's1',
          patientId: 'p1',
          patientName: 'Wangari Njeri',
          kind: 'medical',
          status: 'active',
          triggeredAt: DateTime.now(),
          locationLabel:
              'Plot 47B Ngong Road, opposite the old Kenyatta market gate',
          note: 'Collapsed at the roadside, bystander called it in',
        ),
      ],
    );
    await pumpCard(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Wangari Njeri'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a value carrying prose cannot overflow the line', (
    tester,
  ) async {
    // Real alerts arrive with advice appended to the reading, which is far
    // wider than a bare measurement and used to burst the row.
    seed([
      alert('a0', value: '172/108 mmHg - immediate review required.'),
      alert('a1'),
    ]);
    await pumpCard(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.text('Wangari Njeri'),
      findsOneWidget,
      reason: 'the reading truncates; the patient never does',
    );
    expect(
      tester.getSize(find.byType(UrgentAlertsCard)).height,
      lessThanOrEqualTo(81),
      reason: 'prose in the reading must not grow the band either',
    );

    await unmount(tester);
  });

  testWidgets('prose values survive a narrow screen and a mid-rotation frame', (
    tester,
  ) async {
    seed([
      alert('a0', value: '172/108 mmHg - immediate review required.'),
      alert('a1', value: '88 % - sustained desaturation, escalate now.'),
    ]);
    await pumpCard(tester, width: 320);
    expect(tester.takeException(), isNull);

    // The strip cross-fades one announcement over another, so both lines are
    // laid out in the same frame.
    await tester.pump(UrgentAlertsCard.turn);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await unmount(tester);
  });

  testWidgets('a clear queue keeps the calm line, with nothing invented', (
    tester,
  ) async {
    seed(const []);
    await pumpCard(tester);

    expect(find.text('Nothing urgent outstanding'), findsOneWidget);
    // Ownership and severity belong to alerts; a quiet note has neither.
    expect(find.text('Not yet owned'), findsNothing);
    expect(find.textContaining('critical'), findsNothing);

    await unmount(tester);
  });
}

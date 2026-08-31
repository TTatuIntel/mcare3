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
import 'package:mcare/shared/sos/staff_sos_hub_view.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/app_button.dart';

/// Following an emergency past the moment it stops being yours.
///
/// Handing a case to a provider used to end the coordinator's view of it: the
/// card said "acknowledged" and nothing more, so whether anyone had actually
/// picked it up could only be answered by opening the response sheet. And
/// once closed, the event left the app entirely — there was nothing to follow
/// up at all. These pin that work in progress states its progress, that a
/// closed case still says how it ended, and that the closing confirmation
/// takes itself away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StaffPatient patient(String id, String name) => StaffPatient(
    id: id,
    name: name,
    age: 40,
    sex: 'F',
    condition: 'Hypertension',
    risk: RiskLevel.critical,
    lastReading: DateTime.now(),
    assignedDoctor: 'Dr. Sarah Adeyemi',
  );

  StaffPatientSos handedOver() => StaffPatientSos(
    id: 's1',
    patientId: 'p1',
    patientName: 'Wangari Njeri',
    kind: 'medical',
    status: 'acknowledged',
    triggeredAt: DateTime.now().subtract(const Duration(minutes: 12)),
    respondedBy: 'Dr. Sarah Adeyemi',
    respondedAt: DateTime.now().subtract(const Duration(minutes: 6)),
    progress: [
      SosProgressStep(
        action: 'opened_response',
        label: 'Opened the response',
        actorName: 'Nia Chebet (Admin)',
        at: DateTime.now().subtract(const Duration(minutes: 9)),
      ),
      SosProgressStep(
        action: 'assigned_provider',
        label: 'Handed over to a provider',
        actorName: 'Nia Chebet (Admin)',
        detail: 'Dr. Sarah Adeyemi (care team)',
        at: DateTime.now().subtract(const Duration(minutes: 6)),
      ),
    ],
  );

  StaffPatientSos unowned() => StaffPatientSos(
    id: 's2',
    patientId: 'p2',
    patientName: 'Brian Otieno',
    kind: 'fall',
    status: 'active',
    triggeredAt: DateTime.now().subtract(const Duration(minutes: 2)),
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

  /// The follow-up feed the hub reads for closed cases.
  String closedFeed() =>
      '{"success":true,"data":{"sos_events":[{'
      '"id":"s9","patient_id":"p1","patient_name":"Wangari Njeri",'
      '"kind":"medical","status":"resolved",'
      '"resolution":"patient_safe","resolution_label":"Patient reached and safe",'
      '"responded_by":"Dr. Sarah Adeyemi",'
      '"triggered_at":"${DateTime.now().subtract(const Duration(hours: 2)).toIso8601String()}",'
      '"responded_at":"${DateTime.now().subtract(const Duration(minutes: 80)).toIso8601String()}",'
      '"response_actions":[]}]}}';

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
      MockClient((req) async {
        const json = {'content-type': 'application/json'};
        if (req.url.query.contains('status=all')) {
          return http.Response(closedFeed(), 200, headers: json);
        }
        return http.Response(
          req.method == 'GET' ? '{"success":false}' : '{"success":true}',
          req.method == 'GET' ? 503 : 200,
          headers: json,
        );
      }),
    );
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    AlertCenter.instance.reset();
    SosRingService.instance.stop();
    StaffState.instance.clear();
  });

  Future<void> pumpHub(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const StaffSosHubView()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    SosRingService.instance.stop();
  }

  testWidgets('an emergency being worked says who has it and what was done', (
    tester,
  ) async {
    seed([handedOver()]);
    await pumpHub(tester);

    expect(find.text('In progress — follow up'), findsOneWidget);
    expect(
      find.textContaining('Handed to Dr. Sarah Adeyemi'),
      findsOneWidget,
      reason: 'a coordinator must see where the case went',
    );
    expect(
      find.textContaining('Handed over to a provider'),
      findsOneWidget,
      reason: 'and the last thing that actually happened on it',
    );
    expect(find.textContaining('2 steps'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('an owned emergency with no recorded work says so', (
    tester,
  ) async {
    seed([
      StaffPatientSos(
        id: 's3',
        patientId: 'p1',
        patientName: 'Wangari Njeri',
        kind: 'medical',
        status: 'acknowledged',
        triggeredAt: DateTime.now(),
        respondedBy: 'Dr. Sarah Adeyemi',
      ),
    ]);
    await pumpHub(tester);

    expect(
      find.textContaining('Nothing recorded yet'),
      findsOneWidget,
      reason: 'owned and untouched is exactly what needs chasing',
    );

    await unmount(tester);
  });

  testWidgets('unowned and in-progress are not the same list', (tester) async {
    seed([unowned(), handedOver()]);
    await pumpHub(tester);

    expect(find.text('2 active SOS'), findsOneWidget);
    expect(find.text('In progress — follow up'), findsOneWidget);
    expect(
      find.text('Brian Otieno'),
      findsOneWidget,
      reason: 'the unowned one leads, above the section that is being worked',
    );
    // Wangari appears twice — once being worked, once in the closed list the
    // follow-up feed returns for her earlier emergency.
    expect(find.text('Wangari Njeri'), findsWidgets);
    expect(find.textContaining('Handed to Dr. Sarah Adeyemi'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('a closed emergency is still there to follow up', (tester) async {
    seed(const []);
    await pumpHub(tester);

    expect(find.text('Closed — how they ended'), findsOneWidget);
    expect(
      find.textContaining('Patient reached and safe'),
      findsOneWidget,
      reason: 'the outcome is the point of a follow-up list',
    );
    expect(find.textContaining('by Dr. Sarah Adeyemi'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('the closing confirmation takes itself away', (tester) async {
    // Owned, because closing is only offered to whoever picked it up.
    seed([handedOver()]);
    await pumpHub(tester);

    await tester.tap(find.widgetWithText(AppButton, 'Resolve'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(AppButton, 'Confirm').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(
      find.textContaining('Emergency closed for'),
      findsOneWidget,
      reason: 'the operator is told what finished',
    );

    // …and it stands aside on its own. A confirmation that outlives the
    // moment it confirms becomes furniture on top of the queue.
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Emergency closed for'), findsNothing);
    expect(
      find.text('No active SOS'),
      findsOneWidget,
      reason: 'and leaves the queue it was covering',
    );

    await unmount(tester);
  });

  testWidgets('an emergency nobody picked up cannot be closed from the list', (
    tester,
  ) async {
    seed([unowned()]);
    await pumpHub(tester);

    // Marking an emergency resolved — or a false alarm — without having
    // called the patient, read the chart, or spoken to anyone is not a
    // shortcut, it is a wrong record. Respond first.
    expect(find.widgetWithText(AppButton, 'Resolve'), findsNothing);
    expect(find.widgetWithText(AppButton, 'False alarm'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Respond now'), findsOneWidget);
    expect(
      find.widgetWithText(AppButton, 'Acknowledge — en route'),
      findsOneWidget,
    );
    expect(find.textContaining('before this can be closed'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('picking it up is what opens the outcomes', (tester) async {
    seed([handedOver()]);
    await pumpHub(tester);

    expect(find.widgetWithText(AppButton, 'Resolve'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'False alarm'), findsOneWidget);
    expect(
      find.widgetWithText(AppButton, 'Acknowledge — en route'),
      findsNothing,
      reason: 'it is already owned — there is nothing left to acknowledge',
    );

    await unmount(tester);
  });

  testWidgets('a closed emergency never rejoins the active queue', (
    tester,
  ) async {
    seed(const []);
    await pumpHub(tester);

    expect(find.text('No active SOS'), findsOneWidget);
    expect(
      AlertCenter.instance.openQueue,
      isEmpty,
      reason: 'following up on a closed case must not make it demand attention',
    );

    await unmount(tester);
  });
}

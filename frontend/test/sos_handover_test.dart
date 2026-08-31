import 'dart:convert';

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

/// Handing an emergency to a healthworker, from the responder's side.
///
/// The handover used to be two client-side calls onto the admin assignment
/// CRUD, which refuses a provider who is already assigned — so the care team,
/// the first thing this sheet offers, always came back as "Could not hand
/// over — try again", advice that could not work however many times it was
/// taken. These pin that the care team can be chosen, and that when the
/// server does refuse, the responder is told the actual reason.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The last handover response the fake server should give.
  late int handoverStatus;
  late String handoverBody;
  var handoverCalls = 0;
  Map<String, dynamic>? handoverPayload;

  String action(String name) => jsonEncode({
    'success': true,
    'data': {
      'action': {
        'id': 'a-$name',
        'action': name,
        'label': 'Handed over to a provider',
        'actor_name': 'Nia Chebet (Admin)',
        'detail': 'Dr. Sarah Adeyemi (care team)',
        'created_at': DateTime.now().toIso8601String(),
      },
    },
  });

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

  StaffPatientSos sos() => StaffPatientSos(
    id: 's1',
    patientId: 'p1',
    patientName: 'Amara Okonkwo',
    kind: 'medical',
    status: 'active',
    triggeredAt: DateTime.now(),
    locationLabel: 'Nairobi, Westlands',
  );

  void seed() {
    StaffState.instance.seedFromApi(
      patients: [patient()],
      alerts: const [],
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      sosEvents: [sos()],
    );
  }

  setUp(() {
    handoverStatus = 201;
    handoverBody = action('assigned_provider');
    handoverCalls = 0;
    handoverPayload = null;

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
        final path = req.url.path;

        if (path.endsWith('/handover')) {
          handoverCalls++;
          handoverPayload = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(handoverBody, handoverStatus, headers: json);
        }
        if (path.endsWith('/candidates')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'care_team': [
                  {
                    'provider_id': '77',
                    'user_id': '9',
                    'name': 'Dr. Sarah Adeyemi',
                    'specialty': 'Cardiology',
                    'on_care_team': true,
                    'available': true,
                  },
                ],
                'others': const [],
              },
            }),
            200,
            headers: json,
          );
        }
        if (path.endsWith('/actions')) {
          return http.Response(
            req.method == 'GET'
                ? jsonEncode({
                    'success': true,
                    'data': {'actions': const []},
                  })
                : action('opened_response'),
            req.method == 'GET' ? 200 : 201,
            headers: json,
          );
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

  Future<void> openHandover(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 2200);
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

    await tester.tap(find.text('Respond now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Assign a healthworker'));
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

  testWidgets('the care team can be handed the emergency', (tester) async {
    seed();
    await openHandover(tester);

    expect(
      find.text('Dr. Sarah Adeyemi'),
      findsOneWidget,
      reason: 'the people who know the patient are offered first',
    );

    await tester.tap(find.text('Dr. Sarah Adeyemi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // A sheet now hands control back only once its exit transition has
    // finished, so the work it triggered lands a frame later.
    await tester.pump(const Duration(milliseconds: 600));

    expect(handoverCalls, 1, reason: 'one call, not an assignment then a step');
    expect(handoverPayload?['provider_id'], '77');
    expect(find.textContaining('now has this emergency'), findsOneWidget);
    expect(
      find.textContaining('Handed over to a provider', findRichText: true),
      findsWidgets,
      reason: 'the trail shows the handover without reopening the sheet',
    );

    await settle(tester);
  });

  testWidgets('a refused handover says why, not "try again"', (tester) async {
    handoverStatus = 409;
    handoverBody = jsonEncode({
      'success': false,
      'data': null,
      'message': 'This emergency is already closed.',
    });

    seed();
    await openHandover(tester);

    await tester.tap(find.text('Dr. Sarah Adeyemi'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // A sheet now hands control back only once its exit transition has
    // finished, so the work it triggered lands a frame later.
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('This emergency is already closed.'), findsOneWidget);
    expect(
      find.textContaining('try again'),
      findsNothing,
      reason: 'retrying could never have fixed any of these',
    );

    await settle(tester);
  });
}

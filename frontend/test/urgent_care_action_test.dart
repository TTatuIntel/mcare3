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
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/app_button.dart';
import 'package:mcare/shared/widgets/staff_patient_profile_sheet.dart';

/// The one action offered on a patient's care context.
///
/// The popup used to open on "Acknowledge alert", which made the common path
/// two taps — acknowledge, then find the button again to resolve — and left the
/// alert sitting in the queue after the responder had already dealt with the
/// patient. On a phone the label did not even fit: the actions render two to a
/// row, and it clipped to "Acknowled…".
///
/// It is now a single resolve action. Acknowledgement still happens, as a step
/// inside resolving rather than a button of its own, because resolving does not
/// record who picked the alert up and a second responder needs to see that the
/// case is being worked.
void main() {
  setUp(() {
    // The care context renders its actions only once the chart has loaded, so
    // the chart request has to answer. The parser tolerates missing keys, so
    // the smallest valid envelope is enough.
    ApiClient.instance.setTransportForTesting(
      MockClient(
        (req) async => http.Response(
          '{"success":true,"data":{"patient":{"name":"kib lug"},"window":{}}}',
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    AuthState.instance.signIn(
      const AppUser(
        id: 'd1',
        uniqueId: 'DR-001',
        firstName: 'Kojo',
        lastName: 'Mensah',
        email: 'kojo@mcare.health',
        role: UserRole.doctor,
      ),
    );
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    AuthState.instance.signOut();
    StaffState.instance.clear();
  });

  testWidgets('an unacknowledged alert opens straight on Resolve', (
    tester,
  ) async {
    _seedAlert(acknowledged: false);
    await _openCareContext(tester);

    expect(find.widgetWithText(AppButton, 'Resolve'), findsOneWidget);
    // The two-step path is gone.
    expect(find.textContaining('Acknowledge'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an acknowledged alert offers the same single action', (
    tester,
  ) async {
    _seedAlert(acknowledged: true);
    await _openCareContext(tester);

    expect(find.widgetWithText(AppButton, 'Resolve'), findsOneWidget);
  });

  testWidgets('the label fits the two-per-row action grid on a phone', (
    tester,
  ) async {
    _seedAlert(acknowledged: false);
    await _openCareContext(tester, size: const Size(360, 900));

    // Rendering wider than its slot is what produced "Acknowled…". The text
    // must sit inside the button that holds it.
    final button = tester.getSize(
      find.widgetWithText(AppButton, 'Resolve').first,
    );
    final label = tester.getSize(find.text('Resolve').first);

    expect(label.width, lessThan(button.width));
    expect(tester.takeException(), isNull);
  });
}

void _seedAlert({required bool acknowledged}) {
  StaffState.instance.seedFromApi(
    patients: [
      StaffPatient(
        id: 'p_900',
        name: 'kib lug',
        age: 29,
        sex: 'F',
        condition: 'Hypertension',
        risk: RiskLevel.critical,
        lastReading: DateTime.now(),
        assignedDoctor: 'Dr. Kojo Mensah',
      ),
    ],
    alerts: [
      StaffAlert(
        id: 'a_900',
        patientId: 'p_900',
        patientName: 'kib lug',
        vital: VitalKey.bloodGlucose,
        value: '19.4',
        severity: RiskLevel.critical,
        createdAt: DateTime.now(),
        acknowledged: acknowledged,
        resolved: false,
      ),
    ],
    appointments: const [],
    prescriptions: const [],
    reports: const [],
    vitalRequests: const [],
    careRequests: const [],
    sosEvents: const [],
  );
}

Future<void> _openCareContext(
  WidgetTester tester, {
  Size size = const Size(390, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final item = AlertCenter.instance.openQueue.firstWhere(
    (i) => i.id == 'alert:a_900',
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => StaffPatientProfileSheet.show(
                context,
                patientId: 'p_900',
                patientName: 'kib lug',
                urgentItem: item,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // A critical alert starts the ring, and its periodic timer is checked for
  // at the end of the test body — before tearDown gets a chance to stop it.
  SosRingService.instance.stop();
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/patients/vitals/submit_vital_sheet.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/vitals_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/app_text_field.dart';

/// A patient who has just taken three readings in a row should file them in
/// one pass. The sheet used to accept exactly one vital per open, so a morning
/// round of BP, pulse and weight meant three trips through the same flow —
/// and three chances to give up half way.
///
/// These tests pin both halves of that: one vital on its own still saves
/// exactly as before, and several save together from a single tap.
void main() {
  /// Every POST the sheet issues, in order. There is no batch endpoint, so a
  /// three-vital submission must appear here as three requests — that is the
  /// part of "save them together" the widget tree alone cannot show.
  late List<Map<String, dynamic>> posted;

  setUp(() {
    posted = [];
    // The backend flag is compile-time and defaults to on, so saving takes the
    // real API path. Stubbing the transport keeps that path under test — the
    // request bodies are asserted below — instead of quietly falling back to
    // the offline branch, which is not the code patients run.
    ApiClient.instance.setTransportForTesting(
      MockClient((req) async {
        if (req.method != 'POST' || !req.url.path.endsWith('/patient/vitals')) {
          return http.Response(
            '{"success":true,"data":{}}',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        posted.add(body);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'vital': {
                'id': 'srv_${posted.length}',
                'vital': body['vital_key'],
                'value': body['value'],
                'secondary_value': body['secondary_value'],
                'recorded_at':
                    body['recorded_at'] ?? DateTime.now().toIso8601String(),
                'risk': 'normal',
                'note': body['note'],
              },
            },
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    AuthState.instance.signIn(
      const AppUser(
        id: 'p1',
        uniqueId: 'PT-001',
        firstName: 'Amara',
        lastName: 'Doe',
        email: 'amara@example.com',
        role: UserRole.patient,
      ),
    );
    VitalsState.instance.seedEnabledCatalog(VitalKey.values);
    VitalsState.instance.seedAssigned(const []);
    VitalsState.instance.seedTracked([
      VitalKey.bloodPressure,
      VitalKey.heartRate,
    ]);
    VitalsState.instance.seed(const []);
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    VitalsState.instance.seed(const []);
  });

  testWidgets('a single vital still saves on its own', (tester) async {
    await _openSheet(tester);

    // Only the initial card is open, so Save reads as the plain single action.
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Blood Pressure'), findsOneWidget);
    expect(find.text('Heart Rate'), findsNothing);

    await _type(tester, 'Systolic', '120');
    await _type(tester, 'Diastolic', '80');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = VitalsState.instance.all;
    expect(saved, hasLength(1));
    expect(saved.single.vital, VitalKey.bloodPressure);
    expect(saved.single.value, 120);
    expect(saved.single.secondaryValue, 80);
  });

  testWidgets('several vitals save together from one tap', (tester) async {
    await _openSheet(tester);

    // Tapping a chip opens that vital's card alongside the one already there,
    // rather than replacing it.
    await tester.tap(find.text('HR'));
    await tester.pumpAndSettle();
    expect(find.text('Blood Pressure'), findsOneWidget);
    expect(find.text('Heart Rate'), findsOneWidget);

    await _type(tester, 'Systolic', '128');
    await _type(tester, 'Diastolic', '82');
    await _type(tester, 'Value (bpm)', '74');

    // The button counts what it is about to file.
    expect(find.text('Save 2 vitals'), findsOneWidget);

    await tester.tap(find.text('Save 2 vitals'));
    await tester.pumpAndSettle();

    // One request per reading, both actually sent.
    expect(posted, hasLength(2));
    expect(posted.map((b) => b['vital_key']), ['blood_pressure', 'heart_rate']);
    expect(posted.first['value'], 128);
    expect(posted.first['secondary_value'], 82);
    expect(posted.last['value'], 74);

    final saved = VitalsState.instance.all;
    expect(saved, hasLength(2));
    expect(saved.map((r) => r.vital).toSet(), {
      VitalKey.bloodPressure,
      VitalKey.heartRate,
    });
    final hr = saved.firstWhere((r) => r.vital == VitalKey.heartRate);
    expect(hr.value, 74);
  });

  testWidgets('an opened but unfilled vital is skipped, not rejected', (
    tester,
  ) async {
    await _openSheet(tester);

    // Open heart rate and leave it empty — the patient simply did not take
    // that reading. It must not block the one they did take.
    await tester.tap(find.text('HR'));
    await tester.pumpAndSettle();

    await _type(tester, 'Systolic', '118');
    await _type(tester, 'Diastolic', '76');

    expect(find.text('Save'), findsOneWidget); // one ready, not two
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = VitalsState.instance.all;
    expect(saved, hasLength(1));
    expect(saved.single.vital, VitalKey.bloodPressure);
  });

  testWidgets('a note applies to every reading in the batch', (tester) async {
    await _openSheet(tester);
    await tester.tap(find.text('HR'));
    await tester.pumpAndSettle();

    await _type(tester, 'Systolic', '122');
    await _type(tester, 'Diastolic', '79');
    await _type(tester, 'Value (bpm)', '68');
    await _type(tester, 'Note (optional)', 'before breakfast');

    await tester.tap(find.text('Save 2 vitals'));
    await tester.pumpAndSettle();

    final saved = VitalsState.instance.all;
    expect(saved, hasLength(2));
    expect(saved.every((r) => r.note == 'before breakfast'), isTrue);
  });

  testWidgets('nothing is saved when no reading was entered', (tester) async {
    await _openSheet(tester);

    // Save is inert until at least one vital carries a value, so pressing it
    // on an empty sheet cannot file a blank reading.
    await tester.tap(find.text('Save'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(VitalsState.instance.all, isEmpty);
  });
}

/// Opens the sheet over a bare scaffold so the tests exercise the form itself
/// rather than whichever dashboard happened to launch it.
Future<void> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => SubmitVitalSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Enters [text] into the field carrying [label]. AppTextField draws its
/// label as a sibling of the input, so the field is reached by locating the
/// labelled AppTextField first. Addressing fields by label rather than by
/// position keeps the assertions valid if the cards are ever reordered.
Future<void> _type(WidgetTester tester, String label, String text) async {
  final field = find.descendant(
    of: find.widgetWithText(AppTextField, label),
    matching: find.byType(TextField),
  );
  await tester.enterText(field.first, text);
  await tester.pumpAndSettle();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/staff/staff_assist_gate.dart';
import 'package:mcare/shared/staff/staff_log_vital_sheet.dart';

/// The two things staff could not do from the patient popup.
///
/// The sheet showed a whole clinical snapshot — contact, health profile,
/// assigned vitals — and offered no way to act on any of it. A reading taken at
/// the desk had nowhere to go, and a document the office received went out by
/// email because there was no route into the record. Both now sit directly
/// under the sections they belong to, so the action is where the reader is
/// already looking.
void main() {
  setUp(() {
    StaffState.instance.seedDemo();
  });

  tearDown(() {
    AuthState.instance.signOut();
    StaffState.instance.clear();
  });

  for (final role in [UserRole.doctor, UserRole.admin, UserRole.mcareAssistant]) {
    testWidgets('${role.name} may act on a patient record', (tester) async {
      _signIn(role);
      expect(StaffAssistGate.canAssist(), isTrue);
    });
  }

  testWidgets('a patient may not act on a record as staff', (tester) async {
    // The chart body is also how a patient's own record renders. Offering
    // "log a vital for this patient" to the patient would be nonsense.
    _signIn(UserRole.patient);
    expect(StaffAssistGate.canAssist(), isFalse);
  });

  testWidgets('signed out, nothing is offered', (tester) async {
    AuthState.instance.signOut();
    expect(StaffAssistGate.canAssist(), isFalse);
  });

  testWidgets('the staff reading sheet records for the named patient', (
    tester,
  ) async {
    _signIn(UserRole.doctor);
    await _openLogVitalSheet(tester);

    expect(find.text('Save reading'), findsOneWidget);
    // Recording for someone else is stated, not implied.
    expect(find.textContaining('Amara Okonkwo'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the staff reading sheet refuses an empty value', (tester) async {
    _signIn(UserRole.doctor);
    await _openLogVitalSheet(tester);

    await tester.tap(find.text('Save reading'));
    await tester.pumpAndSettle();
    // The refusal raises a toast holding a 3.5s timer; let it expire so the
    // tree is not torn down with one still pending.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    // Nothing was sent, and the sheet stays open on the entry it needs.
    expect(find.text('Save reading'), findsOneWidget);
  });
}

Future<void> _openLogVitalSheet(WidgetTester tester) async {
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
              onPressed: () => StaffLogVitalSheet.show(
                context,
                patientId: 'p_001',
                patientName: 'Amara Okonkwo',
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
}

void _signIn(UserRole role) {
  AuthState.instance.signIn(
    AppUser(
      id: 's1',
      uniqueId: 'ST-001',
      firstName: 'Nia',
      lastName: 'Chebet',
      email: 'staff@mcare.health',
      role: role,
    ),
  );
}


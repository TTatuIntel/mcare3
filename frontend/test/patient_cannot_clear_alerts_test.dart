import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/patients/vitals/vital_reading_sheet.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/notification_item.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// Closing an alert is a clinical decision, so it belongs to the care team.
///
/// A patient who can dismiss their own critical reading can hide it from the
/// people the alert exists to reach — the screen would look calm while nobody
/// had looked at it. The rule lives in [NotificationState.canResolve] and the
/// patient's screens must not offer an action the server would refuse anyway.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void signIn(UserRole role) {
    AuthState.instance.signIn(
      AppUser(
        id: 'u1',
        uniqueId: 'MCR-000001',
        firstName: 'Test',
        lastName: 'User',
        email: 'test@mcare.health',
        role: role,
      ),
    );
  }

  AppNotification alert() => AppNotification(
    id: 'va_bloodOxygen_1',
    kind: NotificationKind.vitalAlert,
    title: 'Blood oxygen is critical',
    body: '66 % recorded at 12:19 PM',
    createdAt: DateTime.now(),
    actionArguments: VitalKey.bloodOxygen,
  );

  setUp(() => NotificationState.instance.seed([alert()]));

  tearDown(() {
    NotificationState.instance.seed(const []);
    AuthState.instance.signOut();
  });

  test('a patient may not clear a vital alert; the care team may', () {
    final item = alert();

    signIn(UserRole.patient);
    expect(NotificationState.instance.canResolve(item), isFalse);

    for (final role in [
      UserRole.doctor,
      UserRole.admin,
      UserRole.mcareAssistant,
    ]) {
      signIn(role);
      expect(
        NotificationState.instance.canResolve(item),
        isTrue,
        reason: '${role.label} closes alerts',
      );
    }
  });

  test('a patient still clears their own non-clinical notifications', () {
    signIn(UserRole.patient);
    expect(
      NotificationState.instance.canResolve(
        AppNotification(
          id: 'n1',
          kind: NotificationKind.appointment,
          title: 'Appointment confirmed',
          body: 'Tuesday at 10:00',
          createdAt: DateTime.now(),
        ),
      ),
      isTrue,
    );
  });

  test('resolving a vital alert as a patient leaves it open', () {
    signIn(UserRole.patient);

    NotificationState.instance.resolve('va_bloodOxygen_1');

    expect(
      NotificationState.instance.vitalAlertFor(VitalKey.bloodOxygen),
      isNotNull,
    );
  });

  testWidgets('the reading sheet offers the patient no way to clear an alert', (
    tester,
  ) async {
    signIn(UserRole.patient);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => VitalReadingSheet.show(
                  context,
                  reading: VitalReading(
                    id: 'r1',
                    vital: VitalKey.bloodOxygen,
                    value: 66,
                    recordedAt: DateTime.now(),
                    risk: RiskLevel.critical,
                  ),
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

    expect(find.text('Resolve alert'), findsNothing);
    expect(find.textContaining('Your care team clears this alert'), findsOne);
    expect(find.text('View trends & history'), findsOne);
  });
}

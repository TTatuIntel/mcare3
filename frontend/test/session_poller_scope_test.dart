import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/core/realtime/session_poller.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';

void main() {
  setUp(() {
    SessionPoller.instance.detach();
    AuthState.instance.signIn(
      const AppUser(
        id: 'patient-1',
        uniqueId: 'PAT-0001',
        firstName: 'Test',
        lastName: 'Patient',
        email: 'patient@example.test',
        role: UserRole.patient,
      ),
    );
  });

  tearDown(() {
    SessionPoller.instance.detach();
    AuthState.instance.signOut();
  });

  testWidgets(
    'disposing a nested route scope keeps the parent realtime scope alive',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: [
              SessionPollerScope(key: ValueKey('parent'), child: SizedBox()),
              SessionPollerScope(key: ValueKey('detail'), child: SizedBox()),
            ],
          ),
        ),
      );
      await tester.pump();
      expect(SessionPoller.instance.hasAttachedScopes, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: SessionPollerScope(key: ValueKey('parent'), child: SizedBox()),
        ),
      );
      await tester.pump();

      expect(
        SessionPoller.instance.hasAttachedScopes,
        isTrue,
        reason: 'closing a detail route must not stop parent polling',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(SessionPoller.instance.hasAttachedScopes, isFalse);
    },
  );

  test('the same persisted update is presented only once', () {
    const id = 'notification-cross-channel-deduplication';

    expect(SessionPoller.instance.markPatientNotificationSeen(id), isTrue);
    expect(SessionPoller.instance.markPatientNotificationSeen(id), isFalse);
    expect(SessionPoller.instance.markPatientNotificationSeen(null), isTrue);
  });
}

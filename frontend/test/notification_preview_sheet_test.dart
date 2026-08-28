import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/alerts/alert_center.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/notification_item.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/services/sos_ring_service.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/notification_bell.dart';

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

  setUp(() {
    AlertCenter.instance.reset();
    StaffState.instance.clear();
    NotificationState.instance.seed(const []);
  });

  tearDown(() {
    AlertCenter.instance.reset();
    StaffState.instance.clear();
    NotificationState.instance.seed(const []);
    AuthState.instance.signOut();
  });

  testWidgets('bell opens a compact preview and preserves the full inbox', (
    tester,
  ) async {
    signIn(UserRole.patient);
    NotificationState.instance.seed([
      AppNotification(
        id: 'n1',
        kind: NotificationKind.appointment,
        title: 'Appointment confirmed',
        body: 'Tomorrow at 10:00 AM',
        createdAt: DateTime.now(),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        routes: {
          RouteNames.patientNotifications: (_) =>
              const Scaffold(body: Text('Full notification inbox')),
        },
        home: const Scaffold(body: Center(child: NotificationBell())),
      ),
    );

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('1 unread update'), findsOneWidget);
    expect(find.text('Appointment confirmed'), findsOneWidget);
    expect(find.text('Open all notifications'), findsOneWidget);

    await tester.tap(find.text('Open all notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Full notification inbox'), findsOneWidget);
  });

  testWidgets('urgent work is separated from duplicate staff notifications', (
    tester,
  ) async {
    signIn(UserRole.admin);
    StaffState.instance.seedFromApi(
      patients: const [],
      alerts: [
        StaffAlert(
          id: 'a1',
          patientId: 'p1',
          patientName: 'Wangari Njeri',
          vital: VitalKey.bloodPressure,
          value: '190/120',
          severity: RiskLevel.critical,
          createdAt: DateTime.now(),
        ),
      ],
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      sosEvents: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        routes: {
          RouteNames.adminNotifications: (_) =>
              const Scaffold(body: Text('Admin notification inbox')),
        },
        home: const Scaffold(body: Center(child: NotificationBell())),
      ),
    );

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Urgent care queue'), findsOneWidget);
    expect(find.textContaining('Wangari Njeri'), findsOneWidget);
    expect(find.text('No other updates are waiting.'), findsOneWidget);

    await tester.tap(find.byTooltip('Close notifications'));
    await tester.pumpAndSettle();

    // A critical vital rings the device on a repeating timer that deliberately
    // outlives any one screen — in the app it stops when the queue is owned or
    // the session ends. Stop it before the binding's pending-timer check,
    // which runs ahead of tearDown.
    SosRingService.instance.stop();
  });
}

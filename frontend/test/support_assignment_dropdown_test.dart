import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/admin/support/admin_support_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/support_ticket.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/navigation/staff_destinations.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/state/support_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// Opening an assigned ticket used to take the whole sheet down.
///
/// The dropdown's value is the ticket's assignee; its items come from the
/// staff directory. Those are two different lists with two different
/// lifetimes — the directory only ever arrived from `GET /admin/users`, so
/// reaching Support from the dashboard left it empty. A `DropdownButton`
/// whose value matches none of its items is an assertion, not a degraded
/// render: the sheet came up red and the ticket could not be read at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SupportTicket ticket({String? assignedTo, String? assignedToName}) =>
      SupportTicket(
        id: 't1',
        subject: 'Blood pressure cuff pairing lost',
        description: 'The cuff will not pair after the last firmware update.',
        category: TicketCategory.other,
        priority: TicketPriority.high,
        status: TicketStatus.inProgress,
        createdAt: DateTime(2026, 8, 28, 9),
        assignedTo: assignedTo,
        assignedToName: assignedToName,
        patientName: 'Wangari Njeri',
      );

  setUp(() {
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
    SupportState.instance.seed(const []);
    StaffState.instance.clear();
  });

  Future<void> openTicket(WidgetTester tester, SupportTicket t) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SupportState.instance.seed([t]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SupportQueueScreen(
          currentRoute: RouteNames.adminSupport,
          destinations: StaffDestinations.admin(),
          profileRoute: RouteNames.adminProfile,
          notificationsRoute: RouteNames.adminNotifications,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Blood pressure cuff pairing lost').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('an assigned ticket opens with the directory still empty', (
    tester,
  ) async {
    // Exactly the state after tapping Support from the dashboard: the roster
    // has never been fetched, and the ticket is assigned to user 4.
    expect(StaffState.instance.users, isEmpty);

    await openTicket(
      tester,
      ticket(assignedTo: '4', assignedToName: 'Dr. Sarah Adeyemi'),
    );

    expect(
      tester.takeException(),
      isNull,
      reason: 'a value with no matching item asserts and kills the sheet',
    );

    // The assignee is named from the ticket, which knew all along.
    expect(find.text('Dr. Sarah Adeyemi'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an assignee the directory cannot account for is still named', (
    tester,
  ) async {
    // Suspended since the assignment, so filtered out of the assignable list —
    // the same gap, reached a different way.
    StaffState.instance.mergeUsers([
      DirectoryUser(
        id: '4',
        uniqueId: 'MCR-000004',
        name: 'Dr. Sarah Adeyemi',
        email: 'sarah@mcare.health',
        role: UserRole.admin,
        status: 'suspended',
        joinedAt: DateTime(2026, 1, 1),
      ),
      DirectoryUser(
        id: '9',
        uniqueId: 'MCR-000009',
        name: 'Nia Chebet',
        email: 'nia@mcare.health',
        role: UserRole.admin,
        status: 'active',
        joinedAt: DateTime(2026, 1, 1),
      ),
    ]);

    await openTicket(
      tester,
      ticket(assignedTo: '4', assignedToName: 'Dr. Sarah Adeyemi'),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Dr. Sarah Adeyemi'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unassigned ticket still opens', (tester) async {
    await openTicket(tester, ticket());

    expect(tester.takeException(), isNull);
    expect(find.text('Unassigned'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });
}

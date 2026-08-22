import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/admin/approvals/admin_approvals_view.dart';
import 'package:mcare/admin/assignments/admin_assignments_view.dart';
import 'package:mcare/admin/guided_hub/admin_guided_operations_view.dart';
import 'package:mcare/admin/patients/admin_patients_view.dart';
import 'package:mcare/admin/users/admin_users_view.dart';
import 'package:mcare/core/env/app_env.dart';
import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/staff_hub/staff_hub.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

void main() {
  const demoOnly = AppEnv.backendEnabled;

  final targets = <({String name, Widget page, List<String> expected})>[
    (
      name: 'People',
      page: const AdminGuidedOperationsView(
        initialSection: StaffHubSection.people,
        currentRoute: RouteNames.adminPeople,
      ),
      expected: const ['People', 'Patients', 'Users'],
    ),
    (
      name: 'Patients',
      page: const AdminPatientsView(),
      expected: const ['Patients', 'Patient directory', 'Amara Okonkwo'],
    ),
    (
      name: 'Users & passwords',
      page: const AdminUsersView(),
      expected: const ['Users & passwords', 'Amara Okonkwo'],
    ),
    (
      name: 'Healthworker approvals',
      page: const AdminApprovalsView(),
      expected: const ['Healthworker approvals', 'No applications'],
    ),
    (
      name: 'Assignments',
      page: const AdminAssignmentsView(),
      expected: const ['Assignments', 'Care assignments'],
    ),
  ];

  for (final target in targets) {
    testWidgets(
      '${target.name} matches the narrow mobile page contract',
      skip: demoOnly,
      (tester) async {
        StaffState.instance.seedDemo();
        if (target.name == 'Healthworker approvals') {
          StaffState.instance.mergeApprovals(const []);
        }

        await _pumpMobilePage(tester, target.page);

        for (final label in target.expected) {
          expect(find.text(label), findsWidgets);
        }
        for (final destination in const ['Home', 'Work', 'People', 'More']) {
          expect(find.text(destination), findsWidgets);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'assignment End action opens and cancels its confirmation',
    skip: demoOnly,
    (tester) async {
      StaffState.instance.seedDemo();
      await _pumpMobilePage(tester, const AdminAssignmentsView());

      expect(find.text('End'), findsWidgets);
      await tester.tap(find.text('End').first);
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('End assignment?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('End assignment?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'patient search filters rows and its clear action restores them',
    skip: demoOnly,
    (tester) async {
      StaffState.instance.seedDemo();
      await _pumpMobilePage(tester, const AdminPatientsView());

      await tester.enterText(find.byType(TextField).first, 'Amara');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Amara Okonkwo'), findsOneWidget);
      expect(find.text('Wangari Njeri'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Wangari Njeri'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('user role chips filter the account directory', skip: demoOnly, (
    tester,
  ) async {
    StaffState.instance.seedDemo();
    await _pumpMobilePage(tester, const AdminUsersView());

    await tester.tap(find.text('Doctors'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Dr. Kojo Mensah'), findsOneWidget);
    expect(find.text('Amara Okonkwo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'assignment type chips filter care relationships',
    skip: demoOnly,
    (tester) async {
      StaffState.instance.seedDemo();
      await _pumpMobilePage(tester, const AdminAssignmentsView());

      await tester.tap(find.text('Consulting'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('Brian Otieno'), findsOneWidget);
      expect(find.textContaining('Amara Okonkwo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpMobilePage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: page,
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/app_icons.dart';
import 'package:mcare/shared/widgets/role_shell.dart';

const _destinations = <RoleNavDestination>[
  RoleNavDestination(
    icon: AppIcons.home,
    label: 'Home',
    route: RouteNames.adminDashboard,
  ),
  RoleNavDestination(
    icon: AppIcons.assignments,
    label: 'Work',
    route: RouteNames.adminWork,
    activeRoutes: {RouteNames.adminApprovals, RouteNames.adminAssignments},
  ),
  RoleNavDestination(
    icon: AppIcons.users,
    label: 'People',
    route: RouteNames.adminPeople,
    activeRoutes: {RouteNames.adminPatients, RouteNames.adminUsers},
  ),
  RoleNavDestination(
    icon: AppIcons.more,
    label: 'More',
    route: RouteNames.adminMore,
  ),
];

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets(
    'bottom menu stays available and switches tabs from a drill-down',
    (tester) async {
      await _pumpShellApp(tester, initialRoute: RouteNames.adminPeople);

      expect(find.text('people-page'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('People'), findsWidgets);
      expect(find.text('More'), findsOneWidget);

      await tester.tap(find.text('Open patients'));
      await tester.pumpAndSettle();

      expect(find.text('patients-page'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('People'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('home-page'), findsOneWidget);

      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.text('people-page'), findsOneWidget);

      await tester.tap(find.text('Open patients'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();
      expect(find.text('people-page'), findsOneWidget);
    },
  );

  testWidgets('back button returns a deep-linked page to its parent hub', (
    tester,
  ) async {
    await _pumpShellApp(tester, initialRoute: RouteNames.adminPatients);

    expect(find.text('patients-page'), findsOneWidget);
    expect(find.byIcon(AppIcons.backIos), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.backIos));
    await tester.pumpAndSettle();

    expect(find.text('people-page'), findsOneWidget);
    expect(find.byIcon(AppIcons.backIos), findsNothing);
  });

  for (final route in <String>[
    RouteNames.adminPatients,
    RouteNames.adminUsers,
  ]) {
    testWidgets('People menu recovers its hub when opening $route directly', (
      tester,
    ) async {
      await _pumpShellApp(tester, initialRoute: route);

      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();

      expect(find.text('people-page'), findsOneWidget);
    });
  }

  for (final route in <String>[
    RouteNames.adminApprovals,
    RouteNames.adminAssignments,
  ]) {
    testWidgets('Work menu recovers its hub when opening $route directly', (
      tester,
    ) async {
      await _pumpShellApp(tester, initialRoute: route);

      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();

      expect(find.text('work-page'), findsOneWidget);
    });
  }
}

Future<void> _pumpShellApp(
  WidgetTester tester, {
  required String initialRoute,
}) async {
  // Match the narrow mobile width of the supplied reference screens. This
  // catches clipped labels and bottom-rail hit targets that a tablet-sized
  // widget-test surface would miss.
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      onGenerateInitialRoutes: (_) => <Route<void>>[
        MaterialPageRoute<void>(
          settings: RouteSettings(name: initialRoute),
          builder: (_) => _screenFor(initialRoute),
        ),
      ],
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => _screenFor(settings.name ?? ''),
      ),
    ),
  );
  await tester.pump();
}

Widget _screenFor(String route) {
  final (title, marker, action) = switch (route) {
    RouteNames.adminDashboard => ('Home', 'home-page', null),
    RouteNames.adminWork => ('Work', 'work-page', null),
    RouteNames.adminPeople => (
      'People',
      'people-page',
      Builder(
        builder: (context) => FilledButton(
          onPressed: () =>
              Navigator.of(context).pushNamed(RouteNames.adminPatients),
          child: const Text('Open patients'),
        ),
      ),
    ),
    RouteNames.adminMore => ('More', 'more-page', null),
    RouteNames.adminPatients => ('Patients', 'patients-page', null),
    RouteNames.adminUsers => ('Users & passwords', 'users-page', null),
    RouteNames.adminApprovals => (
      'Healthworker approvals',
      'approvals-page',
      null,
    ),
    RouteNames.adminAssignments => ('Assignments', 'assignments-page', null),
    _ => ('Unknown', 'unknown-page', null),
  };

  return RoleShell(
    currentRoute: route,
    destinations: _destinations,
    title: title,
    scrollable: false,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Text(marker), ?action],
      ),
    ),
  );
}

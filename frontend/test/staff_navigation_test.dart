import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/navigation/navigation_roots.dart';
import 'package:mcare/shared/navigation/staff_destinations.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/role_shell.dart';

void main() {
  group('staff destination grouping', () {
    test('target admin screens select the expected persistent tab', () {
      final destinations = StaffDestinations.admin();

      String selectedTab(String route) => destinations
          .singleWhere((destination) => destination.isActive(route))
          .label;

      expect(selectedTab(RouteNames.adminPatients), 'People');
      expect(selectedTab(RouteNames.adminUsers), 'People');
      expect(selectedTab(RouteNames.adminUserDetail), 'People');
      expect(selectedTab(RouteNames.adminApprovals), 'Work');
      expect(selectedTab(RouteNames.adminAssignments), 'Work');
    });

    test('target drill-down screens have stable back fallbacks', () {
      expect(
        NavigationRoots.parentFor(RouteNames.adminPatients),
        RouteNames.adminPeople,
      );
      expect(
        NavigationRoots.parentFor(RouteNames.adminUsers),
        RouteNames.adminPeople,
      );
      expect(
        NavigationRoots.parentFor(RouteNames.adminUserDetail),
        RouteNames.adminUsers,
      );
      expect(
        NavigationRoots.parentFor(RouteNames.adminApprovals),
        RouteNames.adminWork,
      );
      expect(
        NavigationRoots.parentFor(RouteNames.adminAssignments),
        RouteNames.adminWork,
      );

      for (final route in const [
        RouteNames.adminPatients,
        RouteNames.adminUsers,
        RouteNames.adminUserDetail,
        RouteNames.adminApprovals,
        RouteNames.adminAssignments,
      ]) {
        expect(
          NavigationRoots.shouldShowBack(canPop: false, currentRoute: route),
          isTrue,
          reason: '$route must retain a back action after a deep link',
        );
      }
    });
  });

  testWidgets('footer remains usable on a nested People screen', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _StaffNavigationTestApp(initialRoute: RouteNames.adminPeople),
    );
    await tester.pump();

    final peopleContext = tester.element(
      find.byKey(const ValueKey('page:/admin/people')),
    );
    Navigator.of(peopleContext).pushNamed(RouteNames.adminPatients);
    await _finishRouteTransition(tester);

    expect(
      find.byKey(const ValueKey('staff-bottom-nav:/admin/people')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('staff-header-back')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('staff-bottom-nav:/admin/people')),
    );
    await _finishRouteTransition(tester);

    expect(find.byKey(const ValueKey('page:/admin/people')), findsOneWidget);
    expect(find.byKey(const ValueKey('page:/admin/patients')), findsNothing);
  });

  testWidgets('footer tabs keep accessible 48px targets at 360px width', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      const _StaffNavigationTestApp(initialRoute: RouteNames.adminPeople),
    );
    await tester.pump();

    final tabs = <String, String>{
      RouteNames.adminDashboard: 'Home',
      RouteNames.adminWork: 'Work',
      RouteNames.adminPeople: 'People',
      RouteNames.adminMore: 'More',
    };
    final tabRects = <Rect>[];

    for (final entry in tabs.entries) {
      final finder = find.byKey(ValueKey('staff-bottom-nav:${entry.key}'));
      expect(finder, findsOneWidget);

      final semantics = tester.widget<Semantics>(finder).properties;
      expect(semantics.button, isTrue);
      expect(semantics.selected, entry.key == RouteNames.adminPeople);
      expect(semantics.label, '${entry.value} navigation tab');

      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      tabRects.add(tester.getRect(finder));
    }

    for (var index = 0; index < tabRects.length - 1; index++) {
      expect(
        tabRects[index].right,
        lessThanOrEqualTo(tabRects[index + 1].left),
      );
    }
    expect(tabRects.first.left, greaterThanOrEqualTo(0));
    expect(tabRects.last.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deep-link footer and back both recover to the parent hub', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      _StaffNavigationTestApp(initialRoute: RouteNames.adminPatients),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('staff-header-back')));
    await _finishRouteTransition(tester);

    expect(find.byKey(const ValueKey('page:/admin/people')), findsOneWidget);

    final peopleContext = tester.element(
      find.byKey(const ValueKey('page:/admin/people')),
    );
    Navigator.of(peopleContext).pushReplacementNamed(RouteNames.adminPatients);
    await _finishRouteTransition(tester);

    await tester.tap(
      find.byKey(const ValueKey('staff-bottom-nav:/admin/people')),
    );
    await _finishRouteTransition(tester);

    expect(find.byKey(const ValueKey('page:/admin/people')), findsOneWidget);
  });

  testWidgets('deep-linked user detail back returns to the Users directory', (
    tester,
  ) async {
    await _setMobileViewport(tester);
    await tester.pumpWidget(
      const _StaffNavigationTestApp(initialRoute: RouteNames.adminUserDetail),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('staff-header-back')));
    await _finishRouteTransition(tester);

    expect(find.byKey(const ValueKey('page:/admin/users')), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('staff-bottom-nav:/admin/people')),
          )
          .properties
          .selected,
      isTrue,
    );
  });
}

Future<void> _setMobileViewport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _finishRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

class _StaffNavigationTestApp extends StatelessWidget {
  const _StaffNavigationTestApp({required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      initialRoute: initialRoute,
      onGenerateInitialRoutes: (route) => [
        _buildRoute(RouteSettings(name: route)),
      ],
      onGenerateRoute: _buildRoute,
    );
  }

  Route<void> _buildRoute(RouteSettings settings) {
    final route = settings.name ?? RouteNames.adminDashboard;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => RoleShell(
        currentRoute: route,
        destinations: StaffDestinations.admin(),
        title: _titleFor(route),
        scrollable: false,
        padding: EdgeInsets.zero,
        body: SizedBox.expand(key: ValueKey('page:$route'), child: Text(route)),
      ),
    );
  }

  String _titleFor(String route) {
    if (route == RouteNames.adminPatients) return 'Patients';
    if (route == RouteNames.adminApprovals) return 'Healthworker approvals';
    if (route == RouteNames.adminAssignments) return 'Assignments';
    if (route == RouteNames.adminUsers) return 'Users & passwords';
    if (route == RouteNames.adminUserDetail) return 'User';
    return 'People';
  }
}

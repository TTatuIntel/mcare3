import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/patients/meals/meals_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/meal_plan.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/state/meal_plans_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The meals page is a timetable, not a list of notes. What these tests hold
/// to: the day you are looking at drives what you see, a meal can be logged
/// in one gesture from the row itself, progress reflects what was logged, and
/// a day with nothing on it says so rather than showing yesterday's plan.
void main() {
  final today = MealPlansState.dayOf(DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));

  StaffMealPlan plan({
    required String id,
    required String title,
    required DateTime day,
    MealType type = MealType.breakfast,
    String serveTime = '07:00',
    MealAdherence adherence = MealAdherence.pending,
    MealPlanSource source = MealPlanSource.careTeam,
    String? conditionTag,
  }) {
    return StaffMealPlan(
      id: id,
      patientId: 'p1',
      patientName: 'Amara Doe',
      title: title,
      mealType: type,
      assignedAt: today,
      assignedBy: source == MealPlanSource.patient ? 'You' : 'Dr. Mensah',
      scheduledFor: day,
      serveTime: serveTime,
      adherence: adherence,
      source: source,
      conditionTag: conditionTag,
    );
  }

  /// Every adherence log the page issues, in order.
  late List<String> logged;

  setUp(() {
    logged = [];
    // The backend flag is compile-time and defaults to on, so logging takes
    // the real API path. Stubbing the transport keeps that path under test
    // rather than quietly exercising the offline branch patients never run.
    ApiClient.instance.setTransportForTesting(
      MockClient((req) async {
        final match = RegExp(
          r'/patient/meal-plans/([^/]+)/log$',
        ).firstMatch(req.url.path);
        if (req.method != 'POST' || match == null) {
          return http.Response(
            '{"success":true,"data":{}}',
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        final id = match.group(1)!;
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        logged.add('$id:${body['adherence']}');
        final stored = MealPlansState.instance.byId(id)!;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'meal_plan': {
                'id': id,
                'patient_id': stored.patientId,
                'patient_name': stored.patientName,
                'title': stored.title,
                'meal_type': stored.mealType.name,
                'assigned_at': stored.assignedAt.toIso8601String(),
                'assigned_by': stored.assignedBy,
                'scheduled_for': stored.planDate.toIso8601String(),
                'serve_time': stored.serveTime,
                'condition_tag': stored.conditionTag,
                'items': stored.items,
                'source': stored.source.apiValue,
                'adherence': body['adherence'],
                'logged_at': DateTime.now().toIso8601String(),
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

    MealPlansState.instance.seed([
      plan(
        id: 'y1',
        title: 'Yesterday oats',
        day: yesterday,
        adherence: MealAdherence.followed,
      ),
      plan(
        id: 't1',
        title: 'Steel-cut oats',
        day: today,
        conditionTag: 'Type 2 diabetes',
      ),
      plan(
        id: 't2',
        title: 'Grilled fish and greens',
        day: today,
        type: MealType.lunch,
        serveTime: '13:00',
      ),
      plan(
        id: 'm1',
        title: 'Tomorrow omelette',
        day: tomorrow,
      ),
    ]);
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    MealPlansState.instance.seed(const []);
  });

  testWidgets('opens on today and shows only today\'s meals', (tester) async {
    await _pumpMeals(tester);

    expect(find.text('Steel-cut oats'), findsOneWidget);
    expect(find.text('Grilled fish and greens'), findsOneWidget);
    expect(find.text('Yesterday oats'), findsNothing);
    expect(find.text('Tomorrow omelette'), findsNothing);

    // The reason the plan exists travels with it.
    expect(find.text('For Type 2 diabetes'), findsOneWidget);
  });

  testWidgets('meals are grouped under the slot they belong to', (
    tester,
  ) async {
    await _pumpMeals(tester);

    expect(find.text('BREAKFAST'), findsOneWidget);
    expect(find.text('LUNCH'), findsOneWidget);
    expect(find.text('DINNER'), findsNothing);
  });

  testWidgets('a meal can be logged from its own row', (tester) async {
    await _pumpMeals(tester);

    expect(MealPlansState.instance.byId('t1')!.adherence, MealAdherence.pending);

    await tester.tap(find.text('Log').first);
    await _settle(tester);
    await tester.tap(find.text('Followed').last);
    await _settle(tester);

    expect(
      MealPlansState.instance.byId('t1')!.adherence,
      MealAdherence.followed,
    );
    expect(logged, ['t1:followed']);
    expect(find.text('1 of 2 followed'), findsOneWidget);
  });

  testWidgets('"Follow all" closes out the remaining meals on the day', (
    tester,
  ) async {
    await _pumpMeals(tester);

    await tester.tap(find.text('Follow all'));
    await _settle(tester);

    expect(
      MealPlansState.instance
          .plansForDate(today)
          .every((p) => p.adherence == MealAdherence.followed),
      isTrue,
    );
    expect(logged, ['t1:followed', 't2:followed']);
    // Nothing left to close out, so the action retires itself.
    expect(find.text('Follow all'), findsNothing);

    // The confirmation toast owns a dismissal timer; let it expire so the
    // test does not tear the tree down underneath it.
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a future day offers no "Follow all"', (tester) async {
    await _pumpMeals(tester);

    // Selecting tomorrow through the day strip.
    await tester.tap(find.text('${tomorrow.day}').first);
    await _settle(tester);

    expect(find.text('Tomorrow omelette'), findsOneWidget);
    expect(find.text('Follow all'), findsNothing);
  });

  testWidgets('an empty day says so and offers to add a meal', (tester) async {
    MealPlansState.instance.seed(const []);
    await _pumpMeals(tester);

    expect(find.text('Nothing planned for today'), findsOneWidget);
    expect(find.text('Add a meal'), findsOneWidget);
  });

  testWidgets('the floating action is always available', (tester) async {
    await _pumpMeals(tester);
    expect(find.text('Add meal'), findsOneWidget);
  });
}

Future<void> _pumpMeals(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: const MealsView()),
  );
  // Staggered entries plus the day strip's scroll-to-selected animation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Never `pumpAndSettle` here: the floating action button breathes forever by
/// design, so settling never completes. Two framed pumps are enough for a
/// menu route, a state write and the row rebuild that follows.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

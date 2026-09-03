import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mcare/auth/landing_view.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/main.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/auth/session_recovery.dart';
import 'package:mcare/shared/bootstrap/app_bootstrap.dart';
import 'package:mcare/shared/bootstrap/launch_readiness.dart';
import 'package:mcare/shared/constants/route_names.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/navigation/root_navigator.dart';
import 'package:mcare/shared/state/profile_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/pre_login_top_bar.dart';

/// Landing is the app's signed-out face and nothing else. The one thing that
/// must never happen is a live session left looking at it — which is exactly
/// what a bootstrap that threw, timed out, or finished late used to produce,
/// down to the missing Sign in link that gave it away.
void main() {
  const patient = AppUser(
    id: 'p1',
    uniqueId: 'PT-001',
    firstName: 'Amara',
    lastName: 'Doe',
    email: 'amara@example.com',
    role: UserRole.patient,
  );

  setUp(() {
    AppBootstrap.fastMode = true;
    LaunchReadiness.instance.reset();
    ProfileState.instance.clear();
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    ApiClient.instance.setToken(null);
    ApiClient.instance.onSessionRejected = null;
    AuthState.instance.signOut();
    ProfileState.instance.clear();
  });

  void sizePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// A navigator wired like the app's — same key, same observer, the real
  /// [LandingView] — but with placeholder destinations, so these tests measure
  /// the recovery decision instead of every timer a live dashboard starts.
  Future<void> pumpHarness(WidgetTester tester) async {
    sizePhone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        navigatorKey: rootNavigatorKey,
        navigatorObservers: [AppRouteTracker()],
        initialRoute: RouteNames.landing,
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => settings.name == RouteNames.landing
              ? const LandingView()
              : Scaffold(body: Center(child: Text('at ${settings.name}'))),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('a bootstrap that produced no route still lands the session', (
    tester,
  ) async {
    // The headline failure: session restore signs the user in and *then* the
    // watchdog fires, so bootstrap returns nothing. The old code navigated
    // only on the success path and left this user reading marketing copy.
    AuthState.instance.signIn(patient);
    await pumpHarness(tester);

    SessionRecovery.settleLaunch();
    await settle(tester);

    expect(SessionRecovery.currentRoute(), RouteNames.patientDashboard);
  });

  testWidgets('bootstrap reporting "nothing restored" is not a destination', (
    tester,
  ) async {
    AuthState.instance.signIn(patient);
    await pumpHarness(tester);

    SessionRecovery.settleLaunch(bootstrapRoute: RouteNames.home);
    await settle(tester);

    expect(SessionRecovery.currentRoute(), RouteNames.patientDashboard);
  });

  testWidgets('signed out, launch leaves the page it arrived on alone', (
    tester,
  ) async {
    await pumpHarness(tester);

    SessionRecovery.settleLaunch(bootstrapRoute: RouteNames.home);
    await settle(tester);

    expect(SessionRecovery.currentRoute(), RouteNames.landing);
  });

  testWidgets('a web reload keeps the page the user was actually reading', (
    tester,
  ) async {
    AuthState.instance.signIn(patient);
    await pumpHarness(tester);
    rootNavigatorKey.currentState!.pushNamedAndRemoveUntil(
      RouteNames.patientVitals,
      (_) => false,
    );
    await settle(tester);

    SessionRecovery.settleLaunch();
    await settle(tester);

    expect(
      SessionRecovery.currentRoute(),
      RouteNames.patientVitals,
      reason:
          'the role guards vet a deep route; recovery only replaces the '
          'signed-out screens',
    );
  });

  testWidgets('landing hands over as soon as a session arrives', (
    tester,
  ) async {
    await pumpHarness(tester);
    expect(SessionRecovery.currentRoute(), RouteNames.landing);

    // The late restore: the watchdog already fired and landing is on screen.
    AuthState.instance.signIn(patient);
    await settle(tester);

    expect(SessionRecovery.currentRoute(), RouteNames.patientDashboard);
  });

  testWidgets('an unverified account is left on landing on purpose', (
    tester,
  ) async {
    await pumpHarness(tester);
    AuthState.instance.signIn(patient.copyWith(emailVerified: false));
    await settle(tester);

    expect(
      SessionRecovery.currentRoute(),
      RouteNames.landing,
      reason: 'moving it on would re-open the verification sheet it dismissed',
    );
  });

  testWidgets('the real app still boots to landing with nobody signed in', (
    tester,
  ) async {
    sizePhone(tester);
    await tester.pumpWidget(const McareApp());
    await tester.pump(const Duration(seconds: 1));

    expect(SessionRecovery.currentRoute(), RouteNames.landing);
  });

  testWidgets('the pre-login bar always offers a way forward', (tester) async {
    sizePhone(tester);
    Future<void> pumpBar() => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: PreLoginTopBar()),
      ),
    );

    await pumpBar();
    expect(find.text('Sign in'), findsOneWidget);

    // The signed-in case is the safety net: it used to render as empty space,
    // which is how landing ended up with a bare header and no way off it.
    AuthState.instance.signIn(patient);
    await pumpBar();
    await tester.pump();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'the bar must not overflow');
  });

  group('a rejected token ends the session', () {
    void stubStatus(int status, String message) {
      ApiClient.instance.setTransportForTesting(
        MockClient(
          (_) async => http.Response(
            '{"success":false,"message":"$message"}',
            status,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );
    }

    testWidgets('a 401 on an ordinary call signs the user out', (tester) async {
      await pumpHarness(tester);
      AuthState.instance.signIn(patient);
      ApiClient.instance.setToken('stale-token');
      ApiClient.instance.onSessionRejected = SessionRecovery.forceSignOut;
      stubStatus(401, 'Unauthenticated.');

      await expectLater(
        ApiClient.instance.get('/patients/me'),
        throwsA(isA<ApiException>()),
      );
      await settle(tester);

      expect(AuthState.instance.isAuthenticated, isFalse);
      expect(SessionRecovery.currentRoute(), RouteNames.login);
    });

    testWidgets('a 401 from signing in is just a wrong password', (
      tester,
    ) async {
      await pumpHarness(tester);
      AuthState.instance.signIn(patient);
      ApiClient.instance.setToken('live-token');
      ApiClient.instance.onSessionRejected = SessionRecovery.forceSignOut;
      stubStatus(401, 'Invalid credentials.');

      await expectLater(
        ApiClient.instance.post('/auth/login'),
        throwsA(isA<ApiException>()),
      );
      await settle(tester);

      expect(
        AuthState.instance.isAuthenticated,
        isTrue,
        reason: 'a credential endpoint answering 401 is not a dead session',
      );
    });

    testWidgets('a 403 is a permission answer, not a dead session', (
      tester,
    ) async {
      await pumpHarness(tester);
      AuthState.instance.signIn(patient);
      ApiClient.instance.setToken('live-token');
      ApiClient.instance.onSessionRejected = SessionRecovery.forceSignOut;
      stubStatus(403, 'Forbidden.');

      await expectLater(
        ApiClient.instance.get('/admin/users'),
        throwsA(isA<ApiException>()),
      );
      await settle(tester);

      expect(
        AuthState.instance.isAuthenticated,
        isTrue,
        reason: 'an assistant reaching an admin endpoint must stay signed in',
      );
    });
  });
}

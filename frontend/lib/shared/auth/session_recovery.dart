import 'package:flutter/widgets.dart';

import '../constants/route_names.dart';
import '../navigation/root_navigator.dart';
import '../services/auth_service.dart';
import '../state/profile_state.dart';
import '../widgets/app_toast.dart';
import 'auth_state.dart';

/// The single answer to "where does this app belong right now?".
///
/// Launch, a rejected token and a build that blew up all used to guess their
/// own destination, and each guessed differently — which is how a restored
/// session ended up parked on the public landing page with no way forward.
/// They now ask here instead: signed in lands on that role's home (or on
/// whichever gate stands in front of it), signed out lands on landing.
///
/// This does not replace [RoleGuard], [PatientOnboardingGate] or
/// [StaffProfileGate] — those still vet every role route once it is on screen.
/// It only decides which route to hand them.
abstract final class SessionRecovery {
  SessionRecovery._();

  /// Screens that show the app's signed-out face. A restored session must
  /// never be left sitting on one of these; anything else on screen is either
  /// a role route (the guards vet it) or a deep link the user asked for.
  static const _preLogin = <String>{
    RouteNames.home,
    RouteNames.landing,
    RouteNames.login,
    RouteNames.register,
  };

  /// Where the signed-in user belongs — their dashboard, or the gate in front
  /// of it (onboarding, forced password change, pending approval). Landing
  /// when nobody is signed in.
  ///
  /// Delegates to [AuthService.routeForAuthUser] so post-login navigation and
  /// recovery can never drift apart.
  ///
  /// Post-login, `seededProfile` comes from the auth response and is
  /// authoritative. Recovery has no such answer, so it reads the one flag that
  /// distinguishes "the API said there is no health profile" from "it has not
  /// loaded yet" — the same flag [PatientOnboardingGate] gates on. Guessing
  /// from a null profile instead would send a patient to onboarding every time
  /// recovery ran before their record arrived.
  static String homeRoute() {
    final user = AuthState.instance.user;
    if (user == null) return RouteNames.landing;
    return AuthService.instance.routeForAuthUser(
      user,
      !ProfileState.instance.needsOnboarding,
    );
  }

  /// Bare path of the route on screen, with any deep-link query stripped
  /// (`/reset-password?token=x` → `/reset-password`).
  static String? currentRoute() {
    final raw = AppRouteTracker.currentRouteName;
    if (raw == null) return null;
    final path = Uri.tryParse(raw)?.path;
    return (path == null || path.isEmpty) ? raw : path;
  }

  /// Closing step of launch: reconcile what is on screen with the session
  /// bootstrap just restored.
  ///
  /// [bootstrapRoute] is what `AppBootstrap` resolved, or null when it threw
  /// or hit the launch watchdog. Either way this still runs — the whole point
  /// is that a failed bootstrap can no longer strand a live session.
  static void settleLaunch({String? bootstrapRoute}) {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    // `home`/`landing` from bootstrap means "nothing was restored", not a
    // destination — drop it so the checks below get the final word.
    var target = bootstrapRoute;
    if (target == RouteNames.home || target == RouteNames.landing) target = null;

    // Session restore signs the user in *before* it returns a route, so a
    // watchdog timeout or a throw could leave AuthState populated with nobody
    // ever navigating. Ask AuthState directly rather than trusting the return.
    target ??= AuthState.instance.isAuthenticated ? homeRoute() : null;

    // Signed out: whatever is on screen — landing, a reset-password link, the
    // invite page — is already the right answer.
    if (target == null) return;

    final current = currentRoute();
    if (current == target) return;

    // A web reload lands on the URL the user was actually reading
    // (`/patient/vitals`, `/doctor/alerts`). Staying there beats bouncing them
    // to the dashboard, and the role guards already vet it — so only the
    // signed-out screens get replaced.
    if (current != null && !_preLogin.contains(current)) return;

    nav.pushNamedAndRemoveUntil(target, (_) => false);
  }

  /// Sends the app to wherever the current session belongs. Used by surfaces
  /// that have no better answer of their own — the crash fallback, the
  /// pre-login bar, a route that no longer exists.
  static void goHome() {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    final target = homeRoute();
    if (currentRoute() == target) return;
    nav.pushNamedAndRemoveUntil(target, (_) => false);
  }

  /// Ends a session the API has rejected and returns to sign-in.
  ///
  /// This is the "something is wrong with who you are" path: a revoked or
  /// expired token, an account disabled while the app was open. Left alone,
  /// the app keeps looking signed in while every screen fails one request at
  /// a time — so the token goes, the caches go, and the user is told why.
  ///
  /// Idempotent: concurrent requests all failing at once sign out only once,
  /// because [AuthState.signOut] clears the user synchronously.
  static void forceSignOut({
    String reason = 'Your session ended. Please sign in again.',
  }) {
    if (!AuthState.instance.isAuthenticated) return;
    AuthState.instance.signOut();

    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil(RouteNames.login, (_) => false);

    // After the frame: the toast needs the overlay the new route builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = nav.context;
      if (ctx.mounted) AppToast.warn(ctx, reason);
    });
  }
}

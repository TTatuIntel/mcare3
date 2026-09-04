import 'package:flutter/material.dart';

import '../bootstrap/launch_readiness.dart';
import '../constants/route_names.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import 'auth_state.dart';
import 'session_recovery.dart';

/// Wrap any route's widget tree in a `RoleGuard` to enforce auth/role rules.
class RoleGuard extends StatelessWidget {
  const RoleGuard({
    super.key,
    required this.allowed,
    required this.child,
    this.requireApproved = true,
  });

  final List<UserRole> allowed;
  final bool requireApproved;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      // Also listens to launch: a guard built before session restore finishes
      // has to re-decide once it does.
      animation: Listenable.merge([
        AuthState.instance,
        LaunchReadiness.instance,
      ]),
      builder: (_, __) {
        final user = AuthState.instance.user;

        if (user == null) {
          // A web reload of a deep route (`/patient/vitals`) builds this guard
          // before bootstrap has restored the saved session, so "no user" here
          // means "not known yet", not "signed out". Bouncing to sign-in on
          // that frame wiped the stack and — if restore then timed out — left
          // a signed-in user sitting on the login page. Hold instead;
          // BootSplashGate is already covering the frame, and the rebuild
          // above arrives the moment launch settles.
          if (!LaunchReadiness.instance.bootstrapComplete) {
            return const SizedBox.shrink();
          }
          _redirect(context, RouteNames.login);
          return const SizedBox.shrink();
        }
        if (!user.emailVerified) {
          _redirect(context, RouteNames.verifyEmail);
          return const SizedBox.shrink();
        }
        if (requireApproved &&
            user.approvalStatus == ApprovalStatus.pendingApproval) {
          _redirect(context, RouteNames.pendingApproval);
          return const SizedBox.shrink();
        }
        if (!allowed.contains(user.role)) {
          _redirect(context, _homeFor(user.role));
          return const SizedBox.shrink();
        }
        return child;
      },
    );
  }

  void _redirect(BuildContext context, String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
    });
  }

  /// Where a role belongs when it reaches a route that is not its own.
  ///
  /// Kept as the plain dashboard rather than [SessionRecovery.homeRoute]: the
  /// onboarding and profile gates wrapped around each dashboard decide whether
  /// something has to happen first, and asking twice would fight them.
  static String _homeFor(UserRole role) => switch (role) {
    UserRole.patient => RouteNames.patientDashboard,
    UserRole.doctor => RouteNames.doctorDashboard,
    UserRole.admin => RouteNames.adminDashboard,
    UserRole.mcareAssistant => RouteNames.assistantDashboard,
    UserRole.externalDoctor => RouteNames.externalDoctor,
    UserRole.guest => RouteNames.landing,
  };
}

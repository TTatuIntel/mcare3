import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../models/app_user.dart';
import '../models/user_role.dart';
import 'auth_state.dart';

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
      animation: AuthState.instance,
      builder: (_, __) {
        final user = AuthState.instance.user;

        if (user == null) {
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

  static String _homeFor(UserRole role) => switch (role) {
        UserRole.patient => RouteNames.patientDashboard,
        UserRole.doctor => RouteNames.doctorDashboard,
        UserRole.admin => RouteNames.adminDashboard,
        UserRole.mcareAssistant => RouteNames.assistantDashboard,
        UserRole.externalDoctor => RouteNames.externalDoctor,
        UserRole.guest => RouteNames.landing,
      };
}

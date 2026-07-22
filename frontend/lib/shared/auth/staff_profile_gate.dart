import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../models/user_role.dart';
import 'auth_state.dart';

/// Redirects staff (admin, doctor, assistant) to complete profile until
/// name and phone are saved — mirrors [PatientOnboardingGate].
/// Also forces a password change when [AppUser.mustChangePassword] is set.
class StaffProfileGate extends StatelessWidget {
  const StaffProfileGate({
    super.key,
    required this.child,
    required this.completeProfileRoute,
    this.forcePasswordRoute,
  });

  final Widget child;
  final String completeProfileRoute;
  final String? forcePasswordRoute;

  static bool _isStaff(UserRole role) =>
      role == UserRole.admin ||
      role == UserRole.doctor ||
      role == UserRole.mcareAssistant;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        final user = AuthState.instance.user;
        final isStaff = user != null && _isStaff(user.role);
        final needsProfile = isStaff && !user.isProfileComplete;
        final needsPassword = isStaff &&
            user.mustChangePassword &&
            forcePasswordRoute != null;

        final routeName = ModalRoute.of(context)?.settings.name;

        if (needsProfile) {
          if (routeName != completeProfileRoute) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final current = ModalRoute.of(context)?.settings.name;
              if (current == completeProfileRoute) return;
              Navigator.of(context).pushReplacementNamed(completeProfileRoute);
            });
          }
          // Never blank the tree — show content until redirect lands.
          return child;
        }

        if (needsPassword) {
          if (routeName != forcePasswordRoute) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              final current = ModalRoute.of(context)?.settings.name;
              if (current == forcePasswordRoute) return;
              Navigator.of(context).pushReplacementNamed(forcePasswordRoute!);
            });
          }
          return child;
        }

        return child;
      },
    );
  }

  static String completeRouteFor(UserRole role) => switch (role) {
        UserRole.admin => RouteNames.adminCompleteProfile,
        UserRole.doctor => RouteNames.doctorCompleteProfile,
        UserRole.mcareAssistant => RouteNames.assistantCompleteProfile,
        _ => RouteNames.login,
      };

  static String forcePasswordRouteFor(UserRole role) => switch (role) {
        UserRole.admin => RouteNames.adminForcePassword,
        UserRole.doctor => RouteNames.doctorForcePassword,
        UserRole.mcareAssistant => RouteNames.assistantForcePassword,
        _ => RouteNames.login,
      };
}

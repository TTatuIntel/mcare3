import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../state/profile_state.dart';
import 'auth_state.dart';
import '../models/user_role.dart';

/// Redirects new patients to onboarding until health profile is saved.
class PatientOnboardingGate extends StatelessWidget {
  const PatientOnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AuthState.instance, ProfileState.instance]),
      builder: (context, _) {
        final user = AuthState.instance.user;

        // An admin-issued temporary password must be changed before the
        // patient can use the app (mirrors StaffProfileGate for staff roles).
        final mustChangePassword =
            user != null &&
            user.role == UserRole.patient &&
            user.mustChangePassword;
        if (mustChangePassword) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final route = ModalRoute.of(context)?.settings.name;
            if (route == RouteNames.patientForcePassword) return;
            Navigator.of(
              context,
            ).pushReplacementNamed(RouteNames.patientForcePassword);
          });
          return child;
        }

        // Only redirect when the API confirmed there is no health profile.
        // Null health during load must NOT blank profile/settings/SOS.
        final needsOnboarding =
            user != null &&
            user.role == UserRole.patient &&
            ProfileState.instance.needsOnboarding;

        if (needsOnboarding) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final route = ModalRoute.of(context)?.settings.name;
            if (route == RouteNames.patientOnboarding) return;
            Navigator.of(
              context,
            ).pushReplacementNamed(RouteNames.patientOnboarding);
          });
          // Keep showing child until redirect completes — never a blank screen.
          return child;
        }
        return child;
      },
    );
  }
}

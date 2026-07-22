import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../navigation/staff_destinations.dart';
import '../widgets/app_icons.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/role_shell.dart';

/// Permission-gated staff screen — used by mCare assistant routes.
class PermissionGate extends StatelessWidget {
  const PermissionGate({
    super.key,
    required this.permissionKey,
    required this.currentRoute,
    required this.title,
    required this.child,
    this.profileRoute = RouteNames.assistantProfile,
    this.notificationsRoute = RouteNames.assistantNotifications,
    this.destinations,
  });

  final String permissionKey;
  final String currentRoute;
  final String title;
  final Widget child;
  final String profileRoute;
  final String notificationsRoute;
  final List<RoleNavDestination>? destinations;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        if (!AuthState.instance.hasAssistantPermission(permissionKey)) {
          return RoleShell(
            currentRoute: currentRoute,
            destinations: destinations ?? StaffDestinations.assistant(),
            profileRoute: profileRoute,
            notificationsRoute: notificationsRoute,
            title: title,
            subtitle: 'Permission required',
            body: GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.permissions,
                title: 'Permission required',
                message:
                    'Ask an admin to grant the matching permission to access this section.',
                compact: true,
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}

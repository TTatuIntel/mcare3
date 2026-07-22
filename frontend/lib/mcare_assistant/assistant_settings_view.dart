import 'package:flutter/material.dart';

import '../shared/dashboard/admin_workspace_catalog.dart';
import '../shared/auth/auth_state.dart';
import '../shared/constants/route_names.dart';
import '../shared/navigation/staff_destinations.dart';
import '../shared/settings/settings_definitions.dart';
import '../shared/settings/widgets/settings_quick_actions.dart';
import '../shared/settings/widgets/staff_personal_settings_scaffold.dart';
import '../shared/theme/app_colors.dart';
import '../shared/widgets/app_icons.dart';

/// Assistant personal settings — same scaffold as doctor, plus ops shortcuts.
class AssistantSettingsView extends StatelessWidget {
  const AssistantSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final canManageUsers = AuthState.instance
        .hasAssistantPermission(AssistantPermissions.canCreateUsers);
    final openTickets = AdminWorkspaceCounts.openSupport;

    return StaffPersonalSettingsScaffold(
      currentRoute: RouteNames.assistantSettings,
      destinations: StaffDestinations.assistant(),
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
      notificationRole: SettingsNotificationRole.assistant,
      accent: AppColors.info,
      heroTitle: 'Personalise your assistant workspace',
      subtitle: 'Theme, alerts and delegated tools',
      leadingQuickActions: [
        SettingsQuickActionDef(
          icon: AppIcons.support,
          label: 'Ticket inbox',
          badge: openTickets > 0 ? '$openTickets' : null,
          onTap: () =>
              Navigator.of(context).pushNamed(RouteNames.assistantSupport),
        ),
        if (canManageUsers)
          SettingsQuickActionDef(
            icon: AppIcons.lock,
            label: 'Users & passwords',
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.assistantUsers),
          ),
      ],
    );
  }
}

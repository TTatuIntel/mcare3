import 'package:flutter/material.dart';

import '../../shared/account/account_preferences_list.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/settings/settings_definitions.dart';
import '../../shared/settings/widgets/settings_quick_actions.dart';
import '../../shared/settings/widgets/staff_personal_settings_scaffold.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/section_label.dart';
import 'admin_platform_settings_section.dart';

/// Admin personal settings — the shared staff scaffold (appearance, alerts,
/// privacy) plus a trailing platform-administration section unique to admins.
class AdminSettingsView extends StatelessWidget {
  const AdminSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffPersonalSettingsScaffold(
      currentRoute: RouteNames.adminSettings,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
      notificationRole: SettingsNotificationRole.admin,
      accent: AppColors.adminPurple,
      heroTitle: 'Admin workspace preferences',
      subtitle: 'Personal preferences · platform administration',
      leadingQuickActions: [
        SettingsQuickActionDef(
          icon: AppIcons.support,
          label: 'Ticket inbox',
          onTap: () => Navigator.of(context).pushNamed(RouteNames.adminSupport),
        ),
        SettingsQuickActionDef(
          icon: AppIcons.lock,
          label: 'Users & passwords',
          onTap: () => Navigator.of(context).pushNamed(RouteNames.adminUsers),
        ),
        SettingsQuickActionDef(
          icon: AppIcons.system,
          label: 'System',
          onTap: () => Navigator.of(context).pushNamed(RouteNames.adminSystem),
        ),
      ],
      trailingSections: [
        const SizedBox(height: AppSpacing.md),
        const SectionLabel(
          title: 'Platform administration',
          icon: AppIcons.system,
        ),
        const SizedBox(height: AppSpacing.sm),
        const AdminPlatformSettingsSection(),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Open admin workspace',
          icon: AppIcons.home,
          variant: AppButtonVariant.secondary,
          expand: true,
          onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil(
            RouteNames.adminDashboard,
            (_) => false,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SectionLabel(
          title: 'More from your account',
          icon: AppIcons.profile,
        ),
        const SizedBox(height: AppSpacing.sm),
        const AccountHubQuickLinks(
          role: UserRole.admin,
          currentRoute: RouteNames.adminSettings,
        ),
      ],
    );
  }
}

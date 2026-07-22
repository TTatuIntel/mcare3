import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/settings/widgets/settings_link_row.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';

/// Platform administration links — system, permissions, security, audit.
class AdminPlatformSettingsSection extends StatelessWidget {
  const AdminPlatformSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsLinkRow(
            icon: AppIcons.system,
            label: 'System configuration',
            subtitle: 'SMS, signup, retention and runtime flags',
            iconColor: AppColors.adminPurple,
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.adminSystem),
          ),
          Divider(height: 1, color: AppPalette.border(context)),
          SettingsLinkRow(
            icon: AppIcons.permissions,
            label: 'Assistant permissions',
            subtitle: 'Delegate access for mCare assistants',
            iconColor: AppColors.adminPurple,
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.adminPermissions),
          ),
          Divider(height: 1, color: AppPalette.border(context)),
          SettingsLinkRow(
            icon: AppIcons.security,
            label: 'Security incidents',
            subtitle: 'Review and resolve platform incidents',
            iconColor: AppColors.adminPurple,
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.adminSecurity),
          ),
          Divider(height: 1, color: AppPalette.border(context)),
          SettingsLinkRow(
            icon: AppIcons.audit,
            label: 'Audit log',
            subtitle: 'Activity trail across all accounts',
            iconColor: AppColors.adminPurple,
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.adminAudit),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../shared/account/account_preferences_list.dart';
import '../../shared/account/staff_admin_workspace_section.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/profile_completion.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/profile_navigation.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/profile/profile_header_card.dart';
import '../../shared/profile/profile_sections.dart';
import '../../shared/services/admin_session_service.dart';
import '../../shared/settings/widgets/settings_quick_actions.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/profile_completion_heart.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/dashboard/admin_workspace_catalog.dart';

/// Admin profile hub — matches patient/doctor account design with ops workspace.
class AdminProfileView extends StatefulWidget {
  const AdminProfileView({super.key});

  @override
  State<AdminProfileView> createState() => _AdminProfileViewState();
}

class _AdminProfileViewState extends State<AdminProfileView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWorkspace());
  }

  Future<void> _syncWorkspace() async {
    await AdminSessionService.instance.syncFromApi(background: true);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.instance,
      builder: (context, _) {
        final user = AuthState.instance.user;
        if (user == null || user.role != UserRole.admin) {
          return RoleShell(
            scrollable: true,
            currentRoute: RouteNames.adminProfile,
            destinations: StaffDestinations.admin(),
            profileRoute: RouteNames.adminProfile,
            notificationsRoute: RouteNames.adminNotifications,
            title: 'Profile',
            subtitle: 'Profile and administration',
            body: GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.profile,
                title: 'Not signed in',
                message: 'Sign in as an admin to view your profile.',
                compact: true,
              ),
            ),
          );
        }

        final attention = AdminWorkspaceCounts.totalAttention;
        final completion = ProfileCompletion.forUser(user: user);

        return RoleShell(
          scrollable: true,
          currentRoute: RouteNames.adminProfile,
          destinations: StaffDestinations.admin(),
          profileRoute: RouteNames.adminProfile,
          notificationsRoute: RouteNames.adminNotifications,
          title: 'Profile',
          subtitle: 'Profile and administration',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PatientDateHeader(),
              const SizedBox(height: AppSpacing.sm),
              ProfileHeaderCard(
                user: user,
                completionPercent: completion.percent,
                editLabel:
                    user.isProfileComplete ? 'Edit profile' : 'Complete profile',
                onEdit: () =>
                    ProfileNavigation.openEditOrCompleteProfile(context),
                warning: user.isProfileComplete
                    ? null
                    : 'Complete your profile so your workspace is fully set up.',
              ),
              if (!completion.isComplete) ...[
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: ProfileCompletionCard(
                    percent: completion.percent,
                    incompleteLabels:
                        completion.incompleteItems.map((i) => i.label).toList(),
                    onTap: () =>
                        ProfileNavigation.openEditOrCompleteProfile(context),
                  ),
                ),
              ],
              if (attention > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(AppIcons.alert, size: 16, color: AppColors.warning),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          '$attention operational item${attention == 1 ? '' : 's'} need attention',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              ProfileAccountSection(
                user: user,
                onEdit: () =>
                    ProfileNavigation.openEditOrCompleteProfile(context),
              ),
              const SizedBox(height: AppSpacing.md),
              SettingsQuickActionsBar(
                actions: [
                  SettingsQuickActionDef(
                    icon: AppIcons.edit,
                    label: user.isProfileComplete
                        ? 'Edit profile'
                        : 'Complete profile',
                    onTap: () =>
                        ProfileNavigation.openEditOrCompleteProfile(context),
                  ),
                  SettingsQuickActionDef(
                    icon: AppIcons.support,
                    label: 'Ticket inbox',
                    badge: AdminWorkspaceCounts.openSupport > 0
                        ? '${AdminWorkspaceCounts.openSupport}'
                        : null,
                    onTap: () =>
                        Navigator.of(context).pushNamed(RouteNames.adminSupport),
                  ),
                  SettingsQuickActionDef(
                    icon: AppIcons.lock,
                    label: 'Users & passwords',
                    onTap: () =>
                        Navigator.of(context).pushNamed(RouteNames.adminUsers),
                  ),
                  SettingsQuickActionDef(
                    icon: AppIcons.settings,
                    label: 'Settings',
                    onTap: () =>
                        Navigator.of(context).pushNamed(RouteNames.adminSettings),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const StaffAdminWorkspaceSection(),
              const SizedBox(height: AppSpacing.md),
              const SectionLabel(
                title: 'Account & preferences',
                icon: AppIcons.settings,
              ),
              const SizedBox(height: AppSpacing.sm),
              AccountPreferencesList(
                role: UserRole.admin,
                excludeRoutes: {
                  RouteNames.adminSupport,
                  RouteNames.adminUsers,
                  RouteNames.adminAudit,
                },
              ),
              const SizedBox(height: AppSpacing.md),
              const ProfileSecuritySection(),
              const SizedBox(height: AppSpacing.huge),
            ],
          ),
        );
      },
    );
  }
}

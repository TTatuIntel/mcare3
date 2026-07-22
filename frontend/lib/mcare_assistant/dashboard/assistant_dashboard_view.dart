import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/dashboard/admin_workspace_catalog.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/dashboard/staff_attention_builder.dart';
import '../../shared/dashboard/staff_attention_section.dart';
import '../../shared/navigation/sos_navigation.dart';
import '../../shared/models/user_role.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/state/support_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import 'assistant_overview_hero.dart';

class AssistantDashboardView extends StatelessWidget {
  const AssistantDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.assistantDashboard,
      destinations: StaffDestinations.assistant(),
      profileRoute: RouteNames.assistantProfile,
      notificationsRoute: RouteNames.assistantNotifications,
      title: 'Hello, ${AuthState.instance.user?.firstName ?? ''}',
      subtitle:
          'Delegated overview · ${DateFormat.MMMEd().format(DateTime.now())}',
      body: AnimatedBuilder(
        animation: Listenable.merge([
          AuthState.instance,
          StaffState.instance,
          SupportState.instance,
        ]),
        builder: (context, _) {
          final hasPerm = AuthState.instance.hasAssistantPermission;
          final approvals = StaffState.instance.approvals
              .where((a) => a.status == 'pending')
              .toList();
          final requests = StaffState.instance.careRequests
              .where((r) => r.status == 'pending')
              .toList();
          final patients = StaffState.instance.users
              .where((u) => u.role == UserRole.patient && u.status == 'active')
              .length;
          final openAlerts = StaffState.instance.alerts
              .where((a) => !a.acknowledged && !a.resolved)
              .toList();
          final activeSos = StaffState.instance.patientSos
              .where((e) => e.isActive)
              .toList()
            ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
          final grants = AssistantPermissions.all
              .where(hasPerm)
              .toList();
          final attention = StaffAttentionBuilder.build(
            context,
            roleRoutes: AttentionRoleRoutes.assistant,
            hasPermission: hasPerm,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AssistantOverviewHero(),
              const SizedBox(height: AppSpacing.lg),
              StaffAttentionSection(
                title: 'Needs attention',
                items: attention,
              ),
              const SizedBox(height: AppSpacing.lg),
              StaffKpiGrid(
                tiles: [
                  if (hasPerm(AssistantPermissions.canApproveHealthworkers))
                    StaffKpiTile(
                      label: 'Pending approvals',
                      value: '${approvals.length}',
                      icon: AppIcons.approval,
                    ),
                  if (hasPerm(AssistantPermissions.canManageCareRequests))
                    StaffKpiTile(
                      label: 'Care requests',
                      value: '${requests.length}',
                      icon: AppIcons.careRequest,
                    ),
                  StaffKpiTile(
                    label: 'Active patients',
                    value: '$patients',
                    icon: AppIcons.patients,
                  ),
                  StaffKpiTile(
                    label: 'Open alerts',
                    value: '${openAlerts.length}',
                    icon: AppIcons.alert,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              if (hasPerm(AssistantPermissions.canAccessEmergencyLocation)) ...[
                SectionLabel(
                  title: 'Emergency SOS',
                  icon: AppIcons.sos,
                  trailing: '${activeSos.length}',
                  actionLabel: activeSos.isEmpty ? null : 'Respond',
                  onAction: activeSos.isEmpty
                      ? null
                      : () => SosNavigation.openHub(context),
                ),
                if (activeSos.isEmpty)
                  GlassCard(
                    frosted: true,
                    child: Text(
                      'No active SOS events.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else
                  StaffListCard(
                    children: activeSos
                        .take(3)
                        .map((e) => StaffListRow(
                              icon: AppIcons.sos,
                              iconColor: AppColors.critical,
                              title: e.patientName ??
                                  StaffState.instance
                                      .patientById(e.patientId)
                                      ?.name ??
                                  'Patient',
                              subtitle:
                                  '${e.kindLabel} · ${DateFormat.jm().format(e.triggeredAt)}',
                              pill: 'Respond',
                              pillColor: AppColors.critical,
                              onTap: () => SosNavigation.openHub(
                                context,
                                patientId: e.patientId,
                                eventId: e.id,
                              ),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],

              SectionLabel(
                title: 'Your workspaces',
                icon: AppIcons.system,
              ),
              const SizedBox(height: AppSpacing.sm),
              GlassCard(
                frosted: true,
                child: Column(
                  children: AdminWorkspaceCatalog.forAssistantGrants(hasPerm)
                      .where((a) => a.id != 'profile' && a.id != 'dashboard')
                      .take(8)
                      .map(
                        (a) => StaffListRow(
                          icon: a.icon,
                          iconColor: a.color,
                          title: a.label,
                          subtitle: a.subtitle,
                          pill: AdminWorkspaceCounts.badgeFor(a.badgeKey) > 0
                              ? '${AdminWorkspaceCounts.badgeFor(a.badgeKey)}'
                              : null,
                          pillColor: a.color,
                          onTap: () => Navigator.of(context).pushNamed(
                            AdminWorkspaceCatalog.assistantRouteFor(a.id),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              SectionLabel(
                title: 'Your permissions',
                icon: AppIcons.permissions,
                trailing: '${grants.length}/${AssistantPermissions.all.length}',
              ),
              if (grants.isEmpty)
                GlassCard(
                  frosted: true,
                  child: Text(
                    'No permissions delegated yet — contact an admin if you need access.',
                    style: TextStyle(color: AppPalette.textMuted(context)),
                  ),
                )
              else
                GlassCard(
                  frosted: true,
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: grants
                        .map((g) => _PermissionBadge(permKey: g))
                        .toList(),
                  ),
                ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

}

class _PermissionBadge extends StatelessWidget {
  const _PermissionBadge({required this.permKey});
  final String permKey;

  static const _labels = <String, String>{
    'can_approve_healthworkers': 'Approve HW',
    'can_manage_care_requests': 'Care requests',
    'can_assign_patients': 'Assign patients',
    'can_create_users': 'Create users',
    'can_change_user_types': 'Change roles',
    'can_register_admin': 'Register admin',
    'can_register_assistant': 'Register assistant',
    'can_view_activity_logs': 'Activity logs',
    'can_view_security_incidents': 'Security incidents',
    'can_access_emergency_location': 'Emergency SOS',
    'can_manage_advertising': 'Advertising',
    'can_manage_vital_catalog': 'Vital catalog',
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[permKey] ??
        permKey.replaceAll('can_', '').replaceAll('_', ' ');
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: AppColors.mcareAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.mcareAmber,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

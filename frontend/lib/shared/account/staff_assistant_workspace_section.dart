import 'package:flutter/material.dart';

import '../dashboard/admin_workspace_catalog.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../state/staff_state.dart';
import '../state/support_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_icons.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_label.dart';
import '../widgets/staff_blocks.dart';

/// Permission-filtered operations hub for mCare assistants on profile.
class StaffAssistantWorkspaceSection extends StatelessWidget {
  const StaffAssistantWorkspaceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AuthState.instance,
        StaffState.instance,
        SupportState.instance,
      ]),
      builder: (context, _) {
        final has = AuthState.instance.hasAssistantPermission;
        final areas = AdminWorkspaceCatalog.operationsHub()
            .where((a) => a.id != 'permissions' && _areaAllowed(a.id, has))
            .toList();

        if (areas.isEmpty) {
          return GlassCard(
            frosted: true,
            child: Text(
              'No delegated workspace areas yet — contact an admin for access.',
              style: TextStyle(color: AppPalette.textMuted(context)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel(
              title: 'Delegated workspace',
              icon: AppIcons.permissions,
            ),
            const SizedBox(height: AppSpacing.sm),
            GlassCard(
              frosted: true,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      if (has(AssistantPermissions.canApproveHealthworkers))
                        _MetricChip(
                          label: 'Approvals',
                          value: '${AdminWorkspaceCounts.pendingApprovals}',
                          color: AppColors.adminPurple,
                        ),
                      if (has(AssistantPermissions.canManageCareRequests))
                        _MetricChip(
                          label: 'Requests',
                          value: '${AdminWorkspaceCounts.pendingCareRequests}',
                          color: AppColors.info,
                        ),
                      _MetricChip(
                        label: 'Alerts',
                        value: '${AdminWorkspaceCounts.openAlerts}',
                        color: AppColors.warning,
                      ),
                      _MetricChip(
                        label: 'Support',
                        value: '${AdminWorkspaceCounts.openSupport}',
                        color: AppColors.info,
                      ),
                      if (has(AssistantPermissions.canAccessEmergencyLocation))
                        _MetricChip(
                          label: 'SOS',
                          value: '${AdminWorkspaceCounts.activeSos}',
                          color: AppColors.critical,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: AppPalette.border(context)),
                  const SizedBox(height: AppSpacing.sm),
                  StaffListRow(
                    icon: AppIcons.home,
                    title: 'Assistant overview',
                    subtitle: 'Your delegated dashboard',
                    onTap: () => Navigator.of(context)
                        .pushNamed(RouteNames.assistantDashboard),
                  ),
                  for (final area in areas)
                    StaffListRow(
                      icon: area.icon,
                      title: area.label,
                      subtitle: area.subtitle,
                      pill: AdminWorkspaceCounts.badgeFor(area.badgeKey) > 0
                          ? '${AdminWorkspaceCounts.badgeFor(area.badgeKey)}'
                          : null,
                      pillColor: area.color,
                      onTap: () => Navigator.of(context).pushNamed(
                        AdminWorkspaceCatalog.assistantRouteFor(area.id),
                      ),
                    ),
                  if (has(AssistantPermissions.canAccessEmergencyLocation))
                    StaffListRow(
                      icon: AppIcons.sos,
                      title: 'SOS responder hub',
                      subtitle: AdminWorkspaceCounts.activeSos > 0
                          ? '${AdminWorkspaceCounts.activeSos} active emergency event${AdminWorkspaceCounts.activeSos == 1 ? '' : 's'}'
                          : 'No active emergencies',
                      pill: AdminWorkspaceCounts.activeSos > 0 ? '${AdminWorkspaceCounts.activeSos}' : null,
                      pillColor: AppColors.critical,
                      onTap: () =>
                          Navigator.of(context).pushNamed(RouteNames.assistantSos),
                    ),
                  StaffListRow(
                    icon: AppIcons.alert,
                    title: 'System alerts',
                    subtitle: AdminWorkspaceCounts.openAlerts > 0
                        ? '${AdminWorkspaceCounts.openAlerts} need attention'
                        : 'No open alerts',
                    onTap: () => Navigator.of(context)
                        .pushNamed(RouteNames.assistantAlerts),
                  ),
                  StaffListRow(
                    icon: AppIcons.support,
                    title: 'Support inbox',
                    subtitle: AdminWorkspaceCounts.openSupport > 0
                        ? '${AdminWorkspaceCounts.openSupport} open tickets'
                        : 'Inbox clear',
                    onTap: () => Navigator.of(context)
                        .pushNamed(RouteNames.assistantSupport),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static bool _areaAllowed(String id, bool Function(String) has) {
    return switch (id) {
      'users' => has(AssistantPermissions.canCreateUsers),
      'approvals' => has(AssistantPermissions.canApproveHealthworkers),
      'care_requests' => has(AssistantPermissions.canManageCareRequests),
      'assignments' => has(AssistantPermissions.canAssignPatients),
      'support' => true,
      _ => false,
    };
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

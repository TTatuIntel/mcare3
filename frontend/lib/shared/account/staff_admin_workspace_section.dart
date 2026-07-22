import 'package:flutter/material.dart';

import '../dashboard/admin_workspace_catalog.dart';
import '../constants/route_names.dart';
import '../state/staff_state.dart';
import '../state/support_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_icons.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_label.dart';
import '../widgets/staff_blocks.dart';

/// Live admin workspace snapshot on the profile page — full operations hub
/// with metrics and quick links to every core admin capability.
class StaffAdminWorkspaceSection extends StatelessWidget {
  const StaffAdminWorkspaceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        StaffState.instance,
        SupportState.instance,
      ]),
      builder: (context, _) {
        final hubAreas = AdminWorkspaceCatalog.operationsHub();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel(
              title: 'Admin operations hub',
              icon: AppIcons.system,
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
                      _MetricChip(
                        label: 'Approvals',
                        value: '${AdminWorkspaceCounts.pendingApprovals}',
                        color: AppColors.adminPurple,
                      ),
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
                      _MetricChip(
                        label: 'SOS',
                        value: '${AdminWorkspaceCounts.activeSos}',
                        color: AppColors.critical,
                      ),
                    ],
                  ),
                  if (AdminWorkspaceCounts.totalAttention > 0) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(AppIcons.alert,
                              size: 16, color: AppColors.warning),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '${AdminWorkspaceCounts.totalAttention} item${AdminWorkspaceCounts.totalAttention == 1 ? '' : 's'} need your attention',
                              style: TextStyle(
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
                  Divider(height: 1, color: AppPalette.border(context)),
                  const SizedBox(height: AppSpacing.sm),
                  StaffListRow(
                    icon: AppIcons.home,
                    title: 'Admin dashboard',
                    subtitle: 'System overview and KPIs',
                    onTap: () => Navigator.of(context)
                        .pushNamed(RouteNames.adminDashboard),
                  ),
                  for (final area in hubAreas)
                    StaffListRow(
                      icon: area.icon,
                      title: area.label,
                      subtitle: _hubSubtitle(area),
                      pill: _hubPill(area),
                      pillColor: area.color,
                      onTap: () =>
                          Navigator.of(context).pushNamed(area.route),
                    ),
                  StaffListRow(
                    icon: AppIcons.sos,
                    title: 'SOS responder hub',
                    subtitle: AdminWorkspaceCounts.activeSos > 0
                        ? '${AdminWorkspaceCounts.activeSos} active emergency event${AdminWorkspaceCounts.activeSos == 1 ? '' : 's'}'
                        : 'No active emergencies',
                    pill: AdminWorkspaceCounts.activeSos > 0
                        ? '${AdminWorkspaceCounts.activeSos}'
                        : null,
                    pillColor: AppColors.critical,
                    onTap: () =>
                        Navigator.of(context).pushNamed(RouteNames.adminSos),
                  ),
                  StaffListRow(
                    icon: AppIcons.analytics,
                    title: 'Analytics & audit',
                    subtitle: 'Metrics, trends and activity trail',
                    onTap: () => Navigator.of(context)
                        .pushNamed(RouteNames.adminAnalytics),
                  ),
                  StaffListRow(
                    icon: AppIcons.system,
                    title: 'System configuration',
                    subtitle: 'Platform toggles and runtime settings',
                    onTap: () =>
                        Navigator.of(context).pushNamed(RouteNames.adminSystem),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _hubSubtitle(AdminWorkspaceArea area) {
    final badge = AdminWorkspaceCounts.badgeFor(area.badgeKey);
    if (badge > 0) {
      return switch (area.id) {
        'approvals' => '$badge pending healthworker review',
        'care_requests' => '$badge patient request${badge == 1 ? '' : 's'} waiting',
        'support' => '$badge open ticket${badge == 1 ? '' : 's'}',
        _ => area.subtitle,
      };
    }
    return switch (area.id) {
      'approvals' => 'Queue clear',
      'care_requests' => 'No pending requests',
      'support' => 'Inbox clear',
      'users' => 'Create, suspend and reset passwords',
      'permissions' => 'Delegate assistant access',
      'assignments' => 'Manage care team pairings',
      _ => area.subtitle,
    };
  }

  static String? _hubPill(AdminWorkspaceArea area) {
    final badge = AdminWorkspaceCounts.badgeFor(area.badgeKey);
    return badge > 0 ? '$badge' : null;
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

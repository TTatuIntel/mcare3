import 'package:flutter/material.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/models/support_ticket.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/state/support_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';

/// Compact delegated-overview hero for the mCare Assistant dashboard.
class AssistantOverviewHero extends StatelessWidget {
  const AssistantOverviewHero({super.key});

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
        final pendingApprovals = has(AssistantPermissions.canApproveHealthworkers)
            ? StaffState.instance.approvals
                .where((a) => a.status == 'pending')
                .length
            : 0;
        final pendingRequests = has(AssistantPermissions.canManageCareRequests)
            ? StaffState.instance.careRequests
                .where((r) => r.status == 'pending')
                .length
            : 0;
        final openAlerts = StaffState.instance.alerts
            .where((a) => !a.acknowledged && !a.resolved)
            .length;
        final openTickets = SupportState.instance.all
            .where((t) =>
                t.status == TicketStatus.open ||
                t.status == TicketStatus.inProgress)
            .length;
        final activeSos = has(AssistantPermissions.canAccessEmergencyLocation)
            ? StaffState.instance.patientSos.where((e) => e.isActive).length
            : 0;
        final queueTotal =
            pendingApprovals + pendingRequests + openAlerts + activeSos + openTickets;

        final headline = queueTotal == 0
            ? 'Your delegated workspace is clear'
            : '$queueTotal item${queueTotal == 1 ? '' : 's'} need attention';

        return GlassCard(
          frosted: true,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: AppColors.mcareAmber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  queueTotal > 0 ? AppIcons.alert : AppIcons.permissions,
                  color: AppColors.mcareAmber,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      queueTotal == 0
                          ? 'No pending queues in your granted areas.'
                          : 'Review approvals, requests, alerts and support.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        if (pendingApprovals > 0)
                          _HeroChip(
                            label: '$pendingApprovals approvals',
                            color: AppColors.adminPurple,
                          ),
                        if (pendingRequests > 0)
                          _HeroChip(
                            label: '$pendingRequests requests',
                            color: AppColors.info,
                          ),
                        if (openAlerts > 0)
                          _HeroChip(
                            label: '$openAlerts alerts',
                            color: AppColors.warning,
                          ),
                        if (openTickets > 0)
                          _HeroChip(
                            label: '$openTickets support',
                            color: AppColors.info,
                          ),
                        if (activeSos > 0)
                          _HeroChip(
                            label: '$activeSos SOS',
                            color: AppColors.critical,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

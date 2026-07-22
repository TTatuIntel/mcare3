import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/support_ticket.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/sos_navigation.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/state/support_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_card.dart';

/// Single priority banner — no carousel, no duplicate stat row.
class AdminOverviewHero extends StatelessWidget {
  const AdminOverviewHero({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        StaffState.instance,
        SupportState.instance,
      ]),
      builder: (context, _) {
        final banner = _topPriority(context);
        return GlassCard(
          frosted: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: InkWell(
            onTap: banner.onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Row(
              children: [
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: banner.iconBg,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(banner.icon, color: banner.accent, size: 20),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        banner.headline,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        banner.detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppPalette.textMuted(context),
                            ),
                      ),
                    ],
                  ),
                ),
                if (banner.onTap != null)
                  Icon(
                    AppIcons.chevronRight,
                    size: 18,
                    color: banner.accent.withValues(alpha: 0.7),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  _PriorityBanner _topPriority(BuildContext context) {
    final activeSos = StaffState.instance.patientSos
        .where((e) => e.isActive)
        .toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    final openAlerts = StaffState.instance.alerts
        .where((a) => !a.acknowledged && !a.resolved)
        .toList();
    final critical = openAlerts
        .where((a) => a.severity == RiskLevel.critical)
        .length;
    final pendingApprovals = StaffState.instance.approvals
        .where((a) => a.status == 'pending')
        .length;
    final pendingRequests = StaffState.instance.careRequests
        .where((r) => r.status == 'pending')
        .length;
    final openTickets = SupportState.instance.all
        .where((t) =>
            t.status == TicketStatus.open ||
            t.status == TicketStatus.inProgress)
        .length;
    final patients = StaffState.instance.users
        .where((u) => u.role == UserRole.patient && u.status == 'active')
        .length;

    if (activeSos.isNotEmpty) {
      final e = activeSos.first;
      return _PriorityBanner(
        headline:
            '${activeSos.length} active SOS — respond now',
        detail: '${e.patientName ?? 'Patient'} · ${e.kindLabel}',
        icon: AppIcons.sos,
        accent: AppColors.critical,
        iconBg: AppPalette.criticalSoft(context),
        onTap: () => SosNavigation.openHub(
          context,
          patientId: e.patientId,
          eventId: e.id,
        ),
      );
    }

    if (critical > 0) {
      return _PriorityBanner(
        headline: '$critical critical alert${critical == 1 ? '' : 's'}',
        detail: '${openAlerts.length} open across the platform',
        icon: AppIcons.alert,
        accent: AppColors.critical,
        iconBg: AppPalette.criticalSoft(context),
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.adminAlerts),
      );
    }

    if (openAlerts.isNotEmpty) {
      return _PriorityBanner(
        headline: '${openAlerts.length} open alert${openAlerts.length == 1 ? '' : 's'}',
        detail: 'Patient vitals need review',
        icon: AppIcons.alert,
        accent: AppColors.warning,
        iconBg: AppPalette.warningSoft(context),
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.adminAlerts),
      );
    }

    if (pendingApprovals > 0) {
      return _PriorityBanner(
        headline:
            '$pendingApprovals approval${pendingApprovals == 1 ? '' : 's'} pending',
        detail: 'Healthworker registrations awaiting review',
        icon: AppIcons.approval,
        accent: AppColors.adminPurple,
        iconBg: AppColors.adminPurple.withValues(alpha: 0.12),
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.adminApprovals),
      );
    }

    if (pendingRequests > 0) {
      return _PriorityBanner(
        headline:
            '$pendingRequests care request${pendingRequests == 1 ? '' : 's'} waiting',
        detail: 'Route or assign provider changes',
        icon: AppIcons.careRequest,
        accent: AppColors.info,
        iconBg: AppPalette.infoSoft(context),
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.adminCareRequests),
      );
    }

    if (openTickets > 0) {
      return _PriorityBanner(
        headline:
            '$openTickets support ticket${openTickets == 1 ? '' : 's'} open',
        detail: 'Patients and staff awaiting replies',
        icon: AppIcons.support,
        accent: AppColors.info,
        iconBg: AppPalette.infoSoft(context),
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.adminSupport),
      );
    }

    return _PriorityBanner(
      headline: 'All clear',
      detail:
          '$patients active patients · ${DateFormat.jm().format(DateTime.now())}',
      icon: AppIcons.check,
      accent: AppColors.success,
      iconBg: AppPalette.successSoft(context),
    );
  }
}

class _PriorityBanner {
  const _PriorityBanner({
    required this.headline,
    required this.detail,
    required this.icon,
    required this.accent,
    required this.iconBg,
    this.onTap,
  });

  final String headline;
  final String detail;
  final IconData icon;
  final Color accent;
  final Color iconBg;
  final VoidCallback? onTap;
}

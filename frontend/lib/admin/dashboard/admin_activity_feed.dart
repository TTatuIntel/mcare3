import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/sos_navigation.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/section_label.dart';

/// Unified platform activity stream — DailyFlutter-style feed.
class AdminActivityFeed extends StatelessWidget {
  const AdminActivityFeed({super.key, this.limit = 8});

  final int limit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        final entries = _collect().take(limit).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              title: 'Platform activity',
              icon: AppIcons.trend,
              actionLabel: 'Audit log',
              onAction: () =>
                  Navigator.of(context).pushNamed(RouteNames.adminAudit),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (entries.isEmpty)
              GlassCard(
                frosted: true,
                child: EmptyStateView(
                  icon: AppIcons.audit,
                  title: 'No recent activity',
                  message:
                      'Alerts, approvals and audit events will appear here.',
                  compact: true,
                ),
              )
            else
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: AppPalette.border(context)),
                      _FeedRow(entry: entries[i]),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  List<_FeedEntry> _collect() {
    final items = <_FeedEntry>[];

    for (final e in StaffState.instance.patientSos.where((s) => s.isActive)) {
      items.add(_FeedEntry(
        sortAt: e.triggeredAt,
        priority: 100,
        icon: AppIcons.sos,
        accent: AppColors.critical,
        title: 'SOS · ${e.patientName ?? 'Patient'}',
        subtitle: e.kindLabel,
        route: RouteNames.adminSos,
        onTapRoute: true,
        sosPatientId: e.patientId,
        sosEventId: e.id,
      ));
    }

    for (final a in StaffState.instance.alerts
        .where((a) => !a.resolved)
        .take(6)) {
      items.add(_FeedEntry(
        sortAt: a.createdAt,
        priority: a.severity == RiskLevel.critical ? 90 : 70,
        icon: AppIcons.alert,
        accent: a.severity == RiskLevel.critical
            ? AppColors.critical
            : AppColors.warning,
        title: a.patientName,
        subtitle: '${a.vital.label} · ${a.value}',
        route: RouteNames.adminAlerts,
      ));
    }

    for (final a in StaffState.instance.approvals
        .where((a) => a.status == 'pending')
        .take(4)) {
      items.add(_FeedEntry(
        sortAt: a.appliedAt,
        priority: 60,
        icon: AppIcons.approval,
        accent: AppColors.adminPurple,
        title: 'Approval · ${a.name}',
        subtitle: a.specialty,
        route: RouteNames.adminApprovals,
      ));
    }

    for (final e in StaffState.instance.audit.take(6)) {
      items.add(_FeedEntry(
        sortAt: e.at,
        priority: e.category == 'security' ? 55 : 30,
        icon: e.category == 'security' ? AppIcons.security : AppIcons.audit,
        accent: e.category == 'security'
            ? AppColors.critical
            : AppColors.brandIndigo,
        title: e.action,
        subtitle: e.actor,
        route: RouteNames.adminAudit,
      ));
    }

    items.sort((a, b) {
      final byP = b.priority.compareTo(a.priority);
      if (byP != 0) return byP;
      return b.sortAt.compareTo(a.sortAt);
    });
    return items;
  }
}

class _FeedEntry {
  const _FeedEntry({
    required this.sortAt,
    required this.priority,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.route,
    this.onTapRoute = false,
    this.sosPatientId,
    this.sosEventId,
  });

  final DateTime sortAt;
  final int priority;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String route;
  final bool onTapRoute;
  final String? sosPatientId;
  final String? sosEventId;
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.entry});
  final _FeedEntry entry;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.MMMd().add_jm().format(entry.sortAt);
    return InkWell(
      onTap: () {
        if (entry.sosPatientId != null) {
          SosNavigation.openHub(
            context,
            patientId: entry.sosPatientId,
            eventId: entry.sosEventId,
          );
          return;
        }
        Navigator.of(context).pushNamed(entry.route);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                color: entry.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(entry.icon, color: entry.accent, size: 17),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${entry.subtitle} · $time',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight,
                size: 16, color: AppPalette.textMuted(context)),
          ],
        ),
      ),
    );
  }
}

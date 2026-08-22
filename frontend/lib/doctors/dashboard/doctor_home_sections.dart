part of 'doctor_dashboard_view.dart';

/// PDF-approved doctor home composition. The dashboard summarizes the
/// existing caseload and action feed only; it does not imply unsupported EHR,
/// laboratory, imaging, or referral workflows.
class _DoctorHomeLayout extends StatelessWidget {
  const _DoctorHomeLayout({
    required this.assignedCount,
    required this.elevatedCount,
    required this.openAlerts,
    required this.alertDetail,
    required this.alertAccent,
    required this.todayVisits,
    required this.nextVisit,
    required this.activity,
    required this.sosCases,
    required this.onOpenPatients,
    required this.onOpenAlerts,
  });

  final int assignedCount;
  final int elevatedCount;
  final int openAlerts;
  final String alertDetail;
  final Color alertAccent;
  final List<StaffAppointment> todayVisits;
  final StaffAppointment? nextVisit;
  final List<DoctorActivityItem> activity;
  final List<StaffPatientSos> sosCases;
  final VoidCallback onOpenPatients;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final stats = _DoctorMetricGrid(
      items: [
        _DoctorMetricData(
          value: '$assignedCount',
          label: 'Assigned patients',
          detail: elevatedCount > 0
              ? '$elevatedCount need monitoring'
              : 'No elevated patients',
          icon: AppIcons.patients,
          color: Theme.of(context).colorScheme.primary,
          onTap: onOpenPatients,
        ),
        _DoctorMetricData(
          value: '$openAlerts',
          label: 'Open alerts',
          detail: alertDetail,
          icon: AppIcons.alert,
          color: alertAccent,
          onTap: onOpenAlerts,
        ),
        _DoctorMetricData(
          value: '${todayVisits.length}',
          label: 'Visits today',
          detail: nextVisit == null
              ? 'None scheduled'
              : 'Next ${DateFormat.jm().format(nextVisit!.startAt)}',
          icon: AppIcons.appointment,
          color: todayVisits.isEmpty
              ? AppPalette.textMuted(context)
              : AppColors.success,
          onTap: () => Navigator.of(context).pushNamed(RouteNames.doctorVisits),
        ),
      ],
    );

    final priorities = _DoctorPriorityPanel(activity: activity);
    final quickActions = _DoctorQuickActions(sosCases: sosCases);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaggeredEntry(index: 0, child: stats),
            const SizedBox(height: AppSpacing.xl),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: priorities),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 4, child: quickActions),
                ],
              )
            else ...[
              StaggeredEntry(index: 1, child: priorities),
              const SizedBox(height: AppSpacing.xl),
              StaggeredEntry(index: 2, child: quickActions),
            ],
            const SizedBox(height: AppSpacing.huge),
          ],
        );
      },
    );
  }
}

class _DoctorMetricData {
  const _DoctorMetricData({
    required this.value,
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String value;
  final String label;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _DoctorMetricGrid extends StatelessWidget {
  const _DoctorMetricGrid({required this.items});

  final List<_DoctorMetricData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 360 ? 3 : 1;
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _DoctorMetricCard(data: items[i]),
                if (i != items.length - 1)
                  const SizedBox(height: AppSpacing.sm),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Expanded(child: _DoctorMetricCard(data: items[i])),
              if (i != items.length - 1) const SizedBox(width: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

class _DoctorMetricCard extends StatelessWidget {
  const _DoctorMetricCard({required this.data});

  final _DoctorMetricData data;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 210;
        final text = Column(
          crossAxisAlignment: compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              data.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppPalette.ink(context),
              ),
            ),
            Text(
              data.label,
              textAlign: compact ? TextAlign.center : TextAlign.start,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (!compact) ...[
              const SizedBox(height: 2),
              Text(
                data.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            ],
          ],
        );

        return GlassCard(
          onTap: data.onTap,
          constraints: BoxConstraints(minHeight: compact ? 150 : 104),
          padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
          background: data.color.withValues(alpha: 0.045),
          border: Border.all(color: data.color.withValues(alpha: 0.16)),
          child: compact
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _DoctorIconDisc(
                      icon: data.icon,
                      color: data.color,
                      size: 44,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    text,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _DoctorIconDisc(
                      icon: data.icon,
                      color: data.color,
                      size: 48,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: text),
                    Icon(AppIcons.chevronRight, color: data.color, size: 20),
                  ],
                ),
        );
      },
    );
  }
}

class _DoctorPriorityPanel extends StatelessWidget {
  const _DoctorPriorityPanel({required this.activity});

  final List<DoctorActivityItem> activity;

  @override
  Widget build(BuildContext context) {
    final visible = activity.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Needs your action',
          icon: AppIcons.careRequest,
          trailing: activity.isEmpty ? null : '${activity.length}',
          actionLabel: activity.length > visible.length ? 'View all' : null,
          onAction: activity.length > visible.length
              ? () => Navigator.of(context).pushNamed(RouteNames.doctorInbox)
              : null,
        ),
        if (visible.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                const _DoctorIconDisc(
                  icon: AppIcons.check,
                  color: AppColors.success,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'You are caught up. No recent caseload activity needs review.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < visible.length; i++) ...[
            _DoctorPriorityCard(item: visible[i]),
            if (i != visible.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _DoctorPriorityCard extends StatelessWidget {
  const _DoctorPriorityCard({required this.item});

  final DoctorActivityItem item;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: () => Navigator.of(
        context,
      ).pushNamed(item.routeName, arguments: item.routeArguments),
      padding: const EdgeInsets.all(AppSpacing.lg),
      background: item.urgent ? item.iconColor.withValues(alpha: 0.045) : null,
      border: Border.all(
        color: item.urgent
            ? item.iconColor.withValues(alpha: 0.28)
            : AppPalette.border(context),
      ),
      child: Row(
        children: [
          _DoctorIconDisc(icon: item.icon, color: item.iconColor, size: 52),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.urgent) ...[
                  Text(
                    item.pill,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: item.pillColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(AppIcons.chevronRight, color: item.iconColor),
        ],
      ),
    );
  }
}

class _DoctorQuickActions extends StatelessWidget {
  const _DoctorQuickActions({required this.sosCases});

  final List<StaffPatientSos> sosCases;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final actions = [
      _DoctorQuickActionData(
        label: 'Vitals',
        icon: AppIcons.vitals,
        color: primary,
        onTap: () => Navigator.of(context).pushNamed(RouteNames.doctorVitals),
      ),
      _DoctorQuickActionData(
        label: 'Prescriptions',
        icon: AppIcons.medication,
        color: primary,
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.doctorPrescriptions),
      ),
      _DoctorQuickActionData(
        label: 'Reports',
        icon: AppIcons.report,
        color: AppColors.bpPurple,
        onTap: () => Navigator.of(context).pushNamed(RouteNames.doctorReports),
      ),
      _DoctorQuickActionData(
        label: sosCases.isEmpty ? 'SOS' : 'SOS · ${sosCases.length}',
        icon: AppIcons.sos,
        color: AppColors.critical,
        onTap: () => DoctorDashboardView._openSos(context, sosCases),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Quick actions', icon: AppIcons.more),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 600 ? 4 : 2;
            final width =
                (constraints.maxWidth - AppSpacing.md * (columns - 1)) /
                columns;
            return Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: width,
                    child: _DoctorQuickActionTile(data: action),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DoctorQuickActionData {
  const _DoctorQuickActionData({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _DoctorQuickActionTile extends StatelessWidget {
  const _DoctorQuickActionTile({required this.data});

  final _DoctorQuickActionData data;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: data.onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.lg,
      ),
      background: data.color.withValues(alpha: 0.04),
      border: Border.all(color: data.color.withValues(alpha: 0.15)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DoctorIconDisc(icon: data.icon, color: data.color),
          const SizedBox(height: AppSpacing.sm),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _DoctorIconDisc extends StatelessWidget {
  const _DoctorIconDisc({
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.45),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/utils/time_greeting.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/sos_navigation.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/vitals/vital_structure.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_stat_cards.dart';
import 'critical_alert_popup.dart';
import 'doctor_activity_feed.dart';

class DoctorDashboardView extends StatelessWidget {
  const DoctorDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorDashboard,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: timeGreeting(
        firstName: AuthState.instance.user?.firstName,
        prefix: 'Dr. ',
      ),
      subtitle:
          'Caseload overview · ${DateFormat.MMMEd().format(DateTime.now())}',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final assigned = StaffState.instance.assignedPatientsForDoctor();
          final assignedIds = assigned.map((p) => p.id).toSet();
          final alertSummary =
              StaffState.instance.caseloadAlertSummary(patientIds: assignedIds);
          final openAlerts = alertSummary.openCount;
          final criticalAlerts = alertSummary.criticalCount;
          final sosCases = StaffState.instance.patientSos
              .where((e) => assignedIds.contains(e.patientId) && e.isActive)
              .toList();
          final todayAppts = StaffState.instance.appointments
              .where((a) =>
                  a.patientId != null &&
                  assignedIds.contains(a.patientId) &&
                  _isToday(a.startAt))
              .toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
          final elevated = assigned
              .where((p) =>
                  p.risk == RiskLevel.critical ||
                  p.risk == RiskLevel.warning ||
                  p.unreadAlerts > 0)
              .length;
          final activity = DoctorActivityFeed.collect(
            context: context,
            assignedIds: assignedIds,
            patientName: StaffState.instance.patientById,
          );

          final accent = Theme.of(context).colorScheme.primary;
          final nextVisit = todayAppts.isEmpty ? null : todayAppts.first;

          // Fire critical-alert popup once per unseen critical alert in
          // the doctor's caseload. The popup itself dedupes via its
          // internal `_shownIds` set.
          if (criticalAlerts > 0) {
            CriticalAlertPopup.maybeShow(context);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: StaffStatCardsGrid(
                  cards: [
                    StaffStatCardData(
                      value: '${assigned.length}',
                      label: 'Patients',
                      detail: elevated > 0
                          ? '$elevated need monitoring'
                          : 'Caseload stable',
                      icon: AppIcons.patients,
                      accent: accent,
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorPatients),
                    ),
                    StaffStatCardData(
                      value: '$openAlerts',
                      label: 'Alerts',
                      detail: alertSummary.kpiDetail,
                      icon: AppIcons.alert,
                      accent: alertSummary.kpiAccent(),
                      pulse: alertSummary.shouldPulse,
                      cardKey: ValueKey(
                        'alerts-kpi-$openAlerts-${alertSummary.kpiDetail}',
                      ),
                      onTap: () => openCaseloadAlertPrimary(context, alertSummary),
                    ),
                    StaffStatCardData(
                      value: '${todayAppts.length}',
                      label: 'Today',
                      detail: nextVisit != null
                          ? 'Next ${nextVisit.patientName.split(' ').first} ${DateFormat.jm().format(nextVisit.startAt)}'
                          : 'None scheduled',
                      icon: AppIcons.appointment,
                      accent: todayAppts.isNotEmpty
                          ? AppColors.success
                          : AppPalette.textMuted(context),
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorVisits),
                    ),
                    StaffStatCardData(
                      value: '${assigned.length}',
                      label: 'Overview',
                      detail: sosCases.isNotEmpty
                          ? '${sosCases.length} SOS active · open'
                          : 'Trends · adherence · workload',
                      icon: AppIcons.analytics,
                      accent: sosCases.isNotEmpty
                          ? AppColors.critical
                          : AppColors.success,
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorOverview),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: SectionLabel(
                  title: 'Quick actions',
                  icon: AppIcons.more,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 2,
                child: GlassCard(
                  frosted: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs,
                  ),
                  child: PatientQuickActionsBar(
                    children: [
                      PatientQuickAction(
                        icon: AppIcons.vitals,
                        label: 'Vitals',
                        iconColor: accent,
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.doctorVitals),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.alert,
                        label: 'Alerts',
                        iconColor: accent,
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.doctorAlerts),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.careRequest,
                        label: 'Inbox',
                        iconColor: accent,
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.doctorInbox),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.analytics,
                        label: 'Overview',
                        iconColor: accent,
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.doctorOverview),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.sos,
                        label: 'SOS',
                        iconColor: AppColors.critical,
                        badge:
                            sosCases.isNotEmpty ? '${sosCases.length}' : null,
                        badgeColor: AppColors.critical,
                        onTap: () => _openSos(context, sosCases),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: 'Needs your action',
                  icon: AppIcons.careRequest,
                  trailing: activity.isEmpty ? null : '${activity.length}',
                  actionLabel: activity.length >
                          DoctorActivityFeed.dashboardPreviewLimit
                      ? 'View all'
                      : null,
                  onAction: activity.length >
                          DoctorActivityFeed.dashboardPreviewLimit
                      ? () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorInbox)
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 4,
                child: _UpdatesCard(activity: activity),
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  static void _openSos(BuildContext context, List<StaffPatientSos> sosCases) {
    if (sosCases.length == 1) {
      SosNavigation.openRespond(
        context,
        patientId: sosCases.first.patientId,
        eventId: sosCases.first.id,
      );
      return;
    }
    SosNavigation.openHub(
      context,
      patientId: sosCases.isNotEmpty ? sosCases.first.patientId : null,
      eventId: sosCases.isNotEmpty ? sosCases.first.id : null,
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

class _UpdatesCard extends StatelessWidget {
  const _UpdatesCard({required this.activity});

  final List<DoctorActivityItem> activity;

  @override
  Widget build(BuildContext context) {
    if (activity.isEmpty) {
      return GlassCard(
        frosted: true,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(AppIcons.check, color: AppColors.success, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'You\'re caught up — no patient activity in the last ${DoctorActivityFeed.lookbackDays} days.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    final visible =
        activity.take(DoctorActivityFeed.dashboardPreviewLimit).toList();
    final overflow = activity.length - visible.length;
    final urgentCount = activity.where((a) => a.urgent).length;

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              0,
            ),
            child: _LiveHeader(urgentCount: urgentCount),
          ),
          for (var i = 0; i < visible.length; i++)
            _AnimatedUpdateRow(
              key: ValueKey('update-${visible[i].section.name}-${visible[i].at.microsecondsSinceEpoch}-${visible[i].title}'),
              item: visible[i],
              index: i,
            ),
          if (overflow > 0)
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pushNamed(RouteNames.doctorInbox),
              child: Text('+$overflow more updates · open inbox'),
            ),
        ],
      ),
    );
  }
}

class _LiveHeader extends StatefulWidget {
  const _LiveHeader({required this.urgentCount});

  final int urgentCount;

  @override
  State<_LiveHeader> createState() => _LiveHeaderState();
}

class _LiveHeaderState extends State<_LiveHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUrgent = widget.urgentCount > 0;
    final dotColor = hasUrgent ? AppColors.critical : AppColors.success;
    final label = hasUrgent ? 'Live' : 'Live';
    return Row(
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => Container(
            height: 6,
            width: 6,
            decoration: BoxDecoration(
              color: dotColor.withOpacity(0.4 + 0.6 * _pulse.value),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withOpacity(0.5 * _pulse.value),
                  blurRadius: 6 * _pulse.value,
                  spreadRadius: 1 * _pulse.value,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: dotColor,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
        ),
        if (hasUrgent)
          Text(
            ' · ${widget.urgentCount} urgent',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
          ),
      ],
    );
  }
}

class _AnimatedUpdateRow extends StatelessWidget {
  const _AnimatedUpdateRow({
    super.key,
    required this.item,
    required this.index,
  });

  final DoctorActivityItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final delay = Duration(milliseconds: 40 * index);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360) + delay,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 8),
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: item.urgent
            ? BoxDecoration(
                color: item.iconColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border(
                  left: BorderSide(color: item.iconColor, width: 3),
                ),
              )
            : null,
        child: StaffListRow(
          icon: item.icon,
          iconColor: item.iconColor,
          title: item.title,
          subtitle: item.subtitle,
          pill: item.pill,
          pillColor: item.pillColor,
          onTap: () => Navigator.of(context).pushNamed(
            item.routeName,
            arguments: item.routeArguments,
          ),
        ),
      ),
    );
  }
}

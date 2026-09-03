import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/sos_navigation.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/vitals/vital_structure.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_stat_cards.dart';
import 'doctor_action_queue.dart';
import 'doctor_request_queue_cards.dart';

class DoctorActionInboxView extends StatefulWidget {
  const DoctorActionInboxView({super.key});

  @override
  State<DoctorActionInboxView> createState() => _DoctorActionInboxViewState();
}

class _DoctorActionInboxViewState extends State<DoctorActionInboxView> {
  final _queueSectionKey = GlobalKey();

  void _scrollToQueue() {
    final ctx = _queueSectionKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorInbox,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Action inbox',
      subtitle: 'Vitals, alerts & visits across your caseload',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final assigned = StaffState.instance.assignedPatientsForDoctor();
          final assignedIds = assigned.map((p) => p.id).toSet();
          final alertSummary = StaffState.instance.caseloadAlertSummary(
            patientIds: assignedIds,
          );
          final openAlerts = alertSummary.openCount;
          final criticalAlerts = alertSummary.criticalCount;
          final todayAppts =
              StaffState.instance.appointments
                  .where(
                    (a) =>
                        a.patientId != null &&
                        assignedIds.contains(a.patientId) &&
                        _isToday(a.startAt),
                  )
                  .toList()
                ..sort((a, b) => a.startAt.compareTo(b.startAt));
          final elevated = assigned
              .where(
                (p) =>
                    p.risk == RiskLevel.critical ||
                    p.risk == RiskLevel.warning ||
                    p.unreadAlerts > 0,
              )
              .length;
          final sosCount = StaffState.instance.patientSos
              .where((e) => assignedIds.contains(e.patientId) && e.isActive)
              .length;
          final actions = DoctorActionQueue.collect(
            assignedIds: assignedIds,
            patientName: StaffState.instance.patientById,
          );
          // Everything still open, unclaimed first. A request a colleague is
          // already writing up stays on the board — it is not yours to take,
          // but hiding it is how two people end up chasing the same patient.
          final pendingReportRequests =
              StaffState.instance.patientRequests
                  .where(
                    (r) =>
                        r.isOpen &&
                        r.type == 'Vital report' &&
                        assignedIds.contains(r.patientId),
                  )
                  .toList()
                ..sort((a, b) {
                  if (a.isClaimed != b.isClaimed) return a.isClaimed ? 1 : -1;
                  return a.createdAt.compareTo(b.createdAt);
                });
          final openDocumentRequests = StaffState.instance.openDocumentRequests
              .where((r) => assignedIds.contains(r.patientId))
              .toList();
          final accent = Theme.of(context).colorScheme.primary;
          final nextVisit = todayAppts.isEmpty ? null : todayAppts.first;
          final topAction = actions.isEmpty ? null : actions.first;
          final queueDetail = actions.isEmpty
              ? 'All caught up'
              : (sosCount > 0
                    ? '$sosCount SOS active'
                    : '${topAction!.title.split('·').first.trim()} · next up');

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: StaffStatCardsGrid(
                  cards: [
                    StaffStatCardData(
                      value: '$openAlerts',
                      label: 'All alerts',
                      detail: alertSummary.kpiDetail,
                      icon: AppIcons.alert,
                      accent: alertSummary.kpiAccent(),
                      pulse: alertSummary.shouldPulse,
                      cardKey: ValueKey(
                        'inbox-alerts-$openAlerts-${alertSummary.kpiDetail}',
                      ),
                      onTap: () =>
                          openCaseloadAlertPrimary(context, alertSummary),
                    ),
                    StaffStatCardData(
                      value: '${todayAppts.length}',
                      label: 'Today\'s visits',
                      detail: nextVisit != null
                          ? 'Next ${nextVisit.patientName.split(' ').first} ${DateFormat.jm().format(nextVisit.startAt)}'
                          : 'None scheduled',
                      icon: AppIcons.appointment,
                      accent: todayAppts.isNotEmpty
                          ? AppColors.success
                          : AppPalette.textMuted(context),
                      onTap: () => Navigator.of(
                        context,
                      ).pushNamed(RouteNames.doctorVisits),
                    ),
                    StaffStatCardData(
                      value: '${assigned.length}',
                      label: 'Caseload',
                      detail: elevated > 0
                          ? '$elevated need monitoring'
                          : 'Patients assigned to you',
                      icon: AppIcons.patients,
                      accent: accent,
                      onTap: () => Navigator.of(
                        context,
                      ).pushNamed(RouteNames.doctorPatients),
                    ),
                    StaffStatCardData(
                      value: '${actions.length}',
                      label: 'Priority queue',
                      detail: queueDetail,
                      icon: AppIcons.careRequest,
                      accent: actions.isEmpty
                          ? AppPalette.textMuted(context)
                          : (sosCount > 0
                                ? AppColors.critical
                                : AppColors.warning),
                      pulse: sosCount > 0,
                      onTap: actions.isEmpty ? () {} : _scrollToQueue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: const SectionLabel(
                  title: 'Shortcuts',
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
                  child: Column(
                    children: [
                      PatientQuickActionsBar(
                        children: [
                          PatientQuickAction(
                            icon: AppIcons.alert,
                            label: 'Alerts',
                            iconColor: criticalAlerts > 0
                                ? AppColors.critical
                                : AppColors.warning,
                            badge: openAlerts > 0 ? '$openAlerts' : null,
                            badgeColor: criticalAlerts > 0
                                ? AppColors.critical
                                : AppColors.warning,
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(RouteNames.doctorAlerts),
                          ),
                          PatientQuickAction(
                            icon: AppIcons.sos,
                            label: 'SOS',
                            iconColor: AppColors.critical,
                            badge: sosCount > 0 ? '$sosCount' : null,
                            badgeColor: AppColors.critical,
                            onTap: () {
                              if (sosCount == 1) {
                                final e = StaffState.instance.patientSos
                                    .firstWhere(
                                      (x) =>
                                          assignedIds.contains(x.patientId) &&
                                          x.isActive,
                                    );
                                SosNavigation.openRespond(
                                  context,
                                  patientId: e.patientId,
                                  eventId: e.id,
                                );
                              } else {
                                SosNavigation.openHub(context);
                              }
                            },
                          ),
                          PatientQuickAction(
                            icon: AppIcons.appointment,
                            label: 'Visits',
                            iconColor: AppColors.success,
                            badge: todayAppts.isNotEmpty
                                ? '${todayAppts.length}'
                                : null,
                            badgeColor: AppColors.success,
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(RouteNames.doctorVisits),
                          ),
                          PatientQuickAction(
                            icon: AppIcons.patients,
                            label: 'Caseload',
                            iconColor: accent,
                            badge: assigned.isNotEmpty
                                ? '${assigned.length}'
                                : null,
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(RouteNames.doctorPatients),
                          ),
                        ],
                      ),
                      const Divider(height: 1),
                      PatientQuickActionsBar(
                        children: [
                          PatientQuickAction(
                            icon: AppIcons.appointment,
                            label: 'Schedule',
                            iconColor: AppColors.info,
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(RouteNames.doctorAppointments),
                          ),
                          PatientQuickAction(
                            icon: AppIcons.analytics,
                            label: 'Overview',
                            iconColor: accent,
                            onTap: () => Navigator.of(
                              context,
                            ).pushNamed(RouteNames.doctorOverview),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // No care-request triage here: approving or declining a
              // patient's provider request is an admin / mCare-assistant
              // decision. The doctor sees the care team they were assigned.
              if (pendingReportRequests.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 5,
                  child: SectionLabel(
                    title: 'Vital report requests',
                    icon: AppIcons.report,
                    trailing: '${pendingReportRequests.length}',
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                StaggeredEntry(
                  index: 6,
                  child: VitalReportRequestsCard(
                    requests: pendingReportRequests,
                  ),
                ),
              ],
              if (openDocumentRequests.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 7,
                  child: SectionLabel(
                    title: 'Document requests',
                    icon: AppIcons.document,
                    trailing: '${openDocumentRequests.length}',
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                StaggeredEntry(
                  index: 8,
                  child: DocumentRequestsCard(requests: openDocumentRequests),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  key: _queueSectionKey,
                  title: 'Priority queue',
                  icon: AppIcons.careRequest,
                  trailing: actions.isEmpty ? null : '${actions.length}',
                ),
              ),
              if (actions.isEmpty)
                StaggeredEntry(
                  index: 4,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.check,
                      title: 'All caught up',
                      message:
                          'No pending SOS, alerts, or visits need your attention.',
                      compact: true,
                    ),
                  ),
                )
              else
                StaggeredEntry(
                  index: 4,
                  child: StaffListCard(
                    children: actions
                        .map(
                          (item) => StaffListRow(
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
                        )
                        .toList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}

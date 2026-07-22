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
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_stat_cards.dart';
import 'doctor_action_queue.dart';

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
          final alertSummary =
              StaffState.instance.caseloadAlertSummary(patientIds: assignedIds);
          final openAlerts = alertSummary.openCount;
          final criticalAlerts = alertSummary.criticalCount;
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
          final sosCount = StaffState.instance.patientSos
              .where((e) => assignedIds.contains(e.patientId) && e.isActive)
              .length;
          final actions = DoctorActionQueue.collect(
            assignedIds: assignedIds,
            patientName: StaffState.instance.patientById,
          );
          final pendingCareRequests = StaffState.instance.careRequests
              .where((c) => c.status == 'pending')
              .toList();
          final pendingReportRequests = StaffState.instance.patientRequests
              .where((r) =>
                  r.isPending &&
                  r.type == 'Vital report' &&
                  assignedIds.contains(r.patientId))
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
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorVisits),
                    ),
                    StaffStatCardData(
                      value: '${assigned.length}',
                      label: 'Caseload',
                      detail: elevated > 0
                          ? '$elevated need monitoring'
                          : 'Patients assigned to you',
                      icon: AppIcons.patients,
                      accent: accent,
                      onTap: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorPatients),
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
                            onTap: () => Navigator.of(context)
                                .pushNamed(RouteNames.doctorAlerts),
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
                                    .firstWhere((x) =>
                                        assignedIds.contains(x.patientId) &&
                                        x.isActive);
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
                            onTap: () => Navigator.of(context)
                                .pushNamed(RouteNames.doctorVisits),
                          ),
                          PatientQuickAction(
                            icon: AppIcons.patients,
                            label: 'Caseload',
                            iconColor: accent,
                            badge:
                                assigned.isNotEmpty ? '${assigned.length}' : null,
                            onTap: () => Navigator.of(context)
                                .pushNamed(RouteNames.doctorPatients),
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
                            onTap: () => Navigator.of(context)
                                .pushNamed(RouteNames.doctorAppointments),
                          ),
                          PatientQuickAction(
                            icon: AppIcons.analytics,
                            label: 'Overview',
                            iconColor: accent,
                            onTap: () => Navigator.of(context)
                                .pushNamed(RouteNames.doctorOverview),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (pendingCareRequests.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                StaggeredEntry(
                  index: 3,
                  child: SectionLabel(
                    title: 'Care requests',
                    icon: AppIcons.careRequest,
                    trailing: '${pendingCareRequests.length}',
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                StaggeredEntry(
                  index: 4,
                  child: _CareRequestsCard(requests: pendingCareRequests),
                ),
              ],
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
                  child:
                      _VitalReportRequestsCard(requests: pendingReportRequests),
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

// ---------------------------------------------------------------------------
// Care requests card — accept or decline inline
// ---------------------------------------------------------------------------

class _CareRequestsCard extends StatelessWidget {
  const _CareRequestsCard({required this.requests});

  final List<CareRequestItem> requests;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: Column(
        children: requests.asMap().entries.map((entry) {
          final i = entry.key;
          final req = entry.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Icon(
                        AppIcons.careRequest,
                        size: 18,
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            req.patient,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            req.reason.isNotEmpty
                                ? req.reason
                                : 'Requesting care assignment',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppPalette.textMuted(context)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _CareRequestActions(requestId: req.id, patientName: req.patient),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _CareRequestActions extends StatefulWidget {
  const _CareRequestActions({
    required this.requestId,
    required this.patientName,
  });

  final String requestId;
  final String patientName;

  @override
  State<_CareRequestActions> createState() => _CareRequestActionsState();
}

class _CareRequestActionsState extends State<_CareRequestActions> {
  bool _loading = false;

  Future<void> _accept() async {
    setState(() => _loading = true);
    final ok = await StaffState.instance.acceptCareRequestRemote(widget.requestId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      AppToast.success(context, '${widget.patientName} added to your caseload.');
    } else {
      AppToast.error(context, 'Could not accept request. Try again.');
    }
  }

  Future<void> _decline() async {
    setState(() => _loading = true);
    final ok = await StaffState.instance.declineCareRequestRemote(widget.requestId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (!ok) AppToast.error(context, 'Could not decline request. Try again.');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: 'Accept',
          icon: AppIcons.check,
          onPressed: _accept,
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(
          label: 'Decline',
          variant: AppButtonVariant.secondary,
          onPressed: _decline,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Vital report requests card — fulfil or escalate inline
// ---------------------------------------------------------------------------

class _VitalReportRequestsCard extends StatelessWidget {
  const _VitalReportRequestsCard({required this.requests});

  final List<StaffPatientRequest> requests;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: Column(
        children: requests.asMap().entries.map((entry) {
          final i = entry.key;
          final req = entry.value;
          final patientName =
              StaffState.instance.patientById(req.patientId)?.name ?? 'Patient';
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: const Icon(
                        AppIcons.report,
                        size: 18,
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patientName,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            req.summary,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppPalette.textMuted(context)),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _VitalReportActions(
                      requestId: req.id,
                      patientName: patientName,
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _VitalReportActions extends StatefulWidget {
  const _VitalReportActions({
    required this.requestId,
    required this.patientName,
  });

  final String requestId;
  final String patientName;

  @override
  State<_VitalReportActions> createState() => _VitalReportActionsState();
}

class _VitalReportActionsState extends State<_VitalReportActions> {
  bool _loading = false;

  Future<void> _fulfil() async {
    setState(() => _loading = true);
    final ok = await StaffState.instance.fulfillRequest(widget.requestId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      AppToast.success(
        context,
        'Report shared with ${widget.patientName}.',
      );
    } else {
      AppToast.error(context, 'Could not fulfil request. Try again.');
    }
  }

  Future<void> _escalate() async {
    setState(() => _loading = true);
    final ok = await StaffState.instance.escalateRequest(widget.requestId);
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      AppToast.success(context, 'Request escalated to the care team.');
    } else {
      AppToast.error(context, 'Could not escalate request. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: 'Fulfil',
          icon: AppIcons.check,
          onPressed: _fulfil,
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(
          label: 'Escalate',
          variant: AppButtonVariant.secondary,
          onPressed: _escalate,
        ),
      ],
    );
  }
}

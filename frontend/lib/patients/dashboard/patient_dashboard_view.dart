import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/medication.dart';
import '../../shared/navigation/notification_router.dart';
import '../../shared/navigation/vital_navigation.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_motion.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_floating_button.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/section_label.dart';
import '../vitals/submit_vital_sheet.dart';
import '../medications/log_dose_sheet.dart';

part 'patient_dashboard_hero.dart';
part 'patient_dashboard_vitals.dart';

List<Color> _logVitalDynamicColors() {
  var hasCritical = false;
  var hasWarning = false;
  for (final key in VitalsState.instance.tracked) {
    final risk = VitalsState.instance.latestOf(key)?.risk;
    if (risk == RiskLevel.critical) hasCritical = true;
    if (risk == RiskLevel.warning) hasWarning = true;
  }
  if (hasCritical) {
    return [AppColors.critical, AppColors.warning];
  }
  if (hasWarning) {
    return [AppColors.warning, AppColors.brandIndigo];
  }
  return [AppColors.brandIndigo, const Color(0xFF8B5CF6)];
}

class PatientDashboardView extends StatelessWidget {
  const PatientDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientDashboard,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          VitalsState.instance,
          AppointmentsState.instance,
          MedicationsState.instance,
          NotificationState.instance,
        ]),
        builder: (context, _) {
          final tier = ResponsiveBuilder.of(context);
          final appointments = AppointmentsState.instance.upcoming;
          final doses = MedicationsState.instance.dosesForToday();
          final unread = NotificationState.instance.unreadCount;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: PatientDateHeader(),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _HeroInsightCard(
                  doses: doses,
                  appointments: appointments,
                  unreadNotifications: unread,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
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
                        icon: AppIcons.document,
                        label: 'Documents',
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.patientDocuments),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.bell,
                        label: 'Alerts',
                        badge: unread > 0 ? '$unread' : null,
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.patientNotifications),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.support,
                        label: 'Support',
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.patientSupport),
                      ),
                      PatientQuickAction(
                        icon: AppIcons.sos,
                        label: 'SOS',
                        badgeColor: AppColors.critical,
                        onTap: () => Navigator.of(context)
                            .pushNamed(RouteNames.patientSos),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              StaggeredEntry(
                index: 3,
                child: const _RecentVitalsPanel(),
              ),
              const SizedBox(height: AppSpacing.xl),
              StaggeredEntry(
                index: 4,
                child: const SectionLabel(
                  title: 'Activities',
                  icon: AppIcons.trend,
                ),
              ),
              StaggeredEntry(
                index: 5,
                child: const _CareActivityFeed(),
              ),
              if (!tier.isHandheld) ...[
                const SizedBox(height: AppSpacing.xl),
                if (tier.isDesktop)
                  StaggeredEntry(
                    index: 6,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: _UpcomingAppointments(
                              appointments: appointments),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          flex: 5,
                          child: _TodayMeds(doses: doses),
                        ),
                      ],
                    ),
                  )
                else ...[
                  StaggeredEntry(
                      index: 6,
                      child:
                          _UpcomingAppointments(appointments: appointments)),
                  const SizedBox(height: AppSpacing.xl),
                  StaggeredEntry(index: 7, child: _TodayMeds(doses: doses)),
                ],
              ],

              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
      floatingActionButton: ResponsiveBuilder.of(context).isHandheld
          ? ListenableBuilder(
              listenable: VitalsState.instance,
              builder: (context, _) => GlassFloatingButton(
                icon: AppIcons.add,
                label: 'Log vital',
                dynamicColors: _logVitalDynamicColors(),
                onPressed: () => SubmitVitalSheet.show(context),
              ),
            )
          : null,
    );
  }
}

class _CareActivityFeed extends StatefulWidget {
  const _CareActivityFeed();

  @override
  State<_CareActivityFeed> createState() => _CareActivityFeedState();
}

class _CareActivityFeedState extends State<_CareActivityFeed> {
  static const _visibleCount = 7;
  static const _rowExtent = 50.0;

  final _scrollController = ScrollController();
  Timer? _autoScrollTimer;
  Timer? _resumeTimer;
  bool _userInteracting = false;
  int _lastEntryCount = 0;

  List<_ActivityEntry> _entries() {
    final items = <_ActivityEntry>[];

    for (final dose in MedicationsState.instance.dosesForToday()) {
      final isPending = dose.status == DoseStatus.pending;
      items.add(_ActivityEntry(
        sortAt: dose.takenAt ?? dose.scheduledAt,
        priority: isPending ? 90 : 35,
        dose: dose,
      ));
    }

    for (final appt in AppointmentsState.instance.upcoming.take(3)) {
      final isToday = DateUtils.isSameDay(appt.scheduledAt, DateTime.now());
      items.add(_ActivityEntry(
        sortAt: appt.scheduledAt,
        priority: isToday ? 85 : 70,
        appointment: appt,
      ));
    }

    for (final n in NotificationState.instance.activeItems.take(4)) {
      items.add(_ActivityEntry(
        sortAt: n.createdAt,
        priority: n.read ? 25 : 75,
        notification: n,
      ));
    }

    items.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      if (byPriority != 0) return byPriority;
      return b.sortAt.compareTo(a.sortAt);
    });

    return items;
  }

  void _syncAutoScroll(int count) {
    if (count == _lastEntryCount) return;
    _lastEntryCount = count;
    _autoScrollTimer?.cancel();
    if (count > _visibleCount) {
      _startAutoScroll();
    }
  }

  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _userInteracting || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final next = _scrollController.offset + _rowExtent;
      if (next >= max - 2) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      } else {
        _scrollController.animateTo(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userInteracting = true;
      _autoScrollTimer?.cancel();
      _resumeTimer?.cancel();
    } else if (notification is ScrollEndNotification) {
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        _userInteracting = false;
        if (_lastEntryCount > _visibleCount) _startAutoScroll();
      });
    }
    return false;
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _resumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildFeedList(List<_ActivityEntry> entries) {
    final scrollable = entries.length > _visibleCount;

    final list = ListView.separated(
      controller: scrollable ? _scrollController : null,
      physics: scrollable
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      shrinkWrap: !scrollable,
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppPalette.border(context)),
      itemBuilder: (_, i) => _ActivityFeedRow(entry: entries[i]),
    );

    if (!scrollable) return list;

    return SizedBox(
      height: _visibleCount * _rowExtent,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: list,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAutoScroll(entries.length);
    });

    if (entries.isEmpty) {
      return EmptyStateView(
        icon: AppIcons.trend,
        title: 'Nothing here yet',
        message:
            'Log vitals, take medications, or book a visit â€” activity will show up here.',
        actionLabel: 'Log a vital',
        onAction: () => SubmitVitalSheet.show(context),
        compact: true,
      );
    }

    return _buildFeedList(entries);
  }
}

class _ActivityEntry {
  const _ActivityEntry({
    required this.sortAt,
    required this.priority,
    this.dose,
    this.appointment,
    this.notification,
  });

  final DateTime sortAt;
  final int priority;
  final MedicationDose? dose;
  final Appointment? appointment;
  final AppNotification? notification;
}

class _ActivityFeedRow extends StatelessWidget {
  const _ActivityFeedRow({required this.entry});
  final _ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.dose != null) {
      return _MedicationFeedRow(dose: entry.dose!);
    }
    if (entry.appointment != null) {
      return _AppointmentFeedRow(appointment: entry.appointment!);
    }
    if (entry.notification != null) {
      return _NotificationFeedRow(notification: entry.notification!);
    }
    return const SizedBox.shrink();
  }
}

class _MedicationFeedRow extends StatelessWidget {
  const _MedicationFeedRow({required this.dose});
  final MedicationDose dose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTaken = dose.status == DoseStatus.taken;
    final time = DateFormat.jm().format(dose.scheduledAt);
    final when = isTaken && dose.takenAt != null
        ? 'Taken ${_relativeTime(dose.takenAt!)}'
        : 'Due $time';

    return InkWell(
      onTap: () {
        if (isTaken) {
          Navigator.of(context).pushNamed(
            RouteNames.patientMedicationDetail,
            arguments: dose.medicationId,
          );
        } else {
          LogDoseSheet.show(context, dose);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: AppColors.glucoseAmber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(
                AppIcons.medication,
                color: AppColors.glucoseAmber,
                size: 16,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dose.name,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    when,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              dose.dosage,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.glucoseAmber,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _FeedStatusChip(
              label: dose.status.label,
              color: dose.status.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentFeedRow extends StatelessWidget {
  const _AppointmentFeedRow({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(appointment.scheduledAt, DateTime.now());
    final isTomorrow = DateUtils.isSameDay(
      appointment.scheduledAt,
      DateTime.now().add(const Duration(days: 1)),
    );
    final dayLabel = isToday
        ? 'Today'
        : isTomorrow
            ? 'Tomorrow'
            : DateFormat.MMMd().format(appointment.scheduledAt);
    final time = DateFormat.jm().format(appointment.scheduledAt);

    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(
        RouteNames.patientAppointmentDetail,
        arguments: appointment.id,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: AppColors.bpPurple.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: const Icon(
                AppIcons.appointment,
                color: AppColors.bpPurple,
                size: 16,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.doctorName,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$dayLabel Â· $time',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              appointment.type.label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: AppColors.bpPurple,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _FeedStatusChip(
              label: appointment.status.label,
              color: appointment.status.color,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationFeedRow extends StatelessWidget {
  const _NotificationFeedRow({required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = notification.kind.tint;
    final isVitalAlert = notification.kind == NotificationKind.vitalAlert;

    return InkWell(
      onTap: () => NotificationRouter.handleTap(context, notification),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(notification.kind.icon, color: accent, size: 16),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight:
                          notification.read ? FontWeight.w600 : FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    notification.body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isVitalAlert)
              IconButton(
                tooltip: 'Mark resolved',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  NotificationState.instance.resolveRemote(notification.id);
                  AppToast.success(context, 'Alert resolved and cleared.');
                },
                icon: const Icon(AppIcons.check, size: 18),
                color: AppColors.success,
              )
            else if (!notification.read)
              Container(
                height: 8,
                width: 8,
                decoration: const BoxDecoration(
                  color: AppColors.critical,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeedStatusChip extends StatelessWidget {
  const _FeedStatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _relativeTime(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays == 1) return 'Yesterday';
  return DateFormat.MMMd().format(at);
}

class _UpcomingAppointments extends StatelessWidget {
  const _UpcomingAppointments({required this.appointments});
  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Upcoming appointments',
          icon: AppIcons.appointment,
          actionLabel: 'See all',
          onAction: () => Navigator.of(context)
              .pushNamed(RouteNames.patientAppointments),
        ),
        if (appointments.isEmpty)
          EmptyStateView(
            icon: AppIcons.appointment,
            title: 'No appointments',
            message: 'Book a visit with your care team.',
            actionLabel: 'Book appointment',
            onAction: () => Navigator.of(context)
                .pushNamed(RouteNames.patientAppointments),
            compact: true,
          )
        else
          Column(
            children: [
              for (var i = 0; i < appointments.take(3).length; i++) ...[
                if (i > 0)
                  Divider(height: 1, color: AppPalette.border(context)),
                _AppointmentCard(a: appointments[i]),
              ],
            ],
          ),
      ],
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.a});
  final Appointment a;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(a.scheduledAt, DateTime.now());
    final isTomorrow = DateUtils.isSameDay(
        a.scheduledAt, DateTime.now().add(const Duration(days: 1)));
    final dayLabel = isToday
        ? 'Today'
        : isTomorrow
            ? 'Tomorrow'
            : DateFormat.MMMEd().format(a.scheduledAt);
    final time = DateFormat.jm().format(a.scheduledAt);

    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(
        RouteNames.patientAppointmentDetail,
        arguments: a.id,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.bpPurple.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat.d().format(a.scheduledAt),
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.bpPurple,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    DateFormat.MMM().format(a.scheduledAt).toUpperCase(),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.bpPurple),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.doctorName,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis),
                  Text(a.doctorSpecialty,
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(_typeIcon(a.type),
                          size: 14, color: AppPalette.textMuted(context)),
                      const SizedBox(width: 4),
                      Text(
                        '${a.type.label} Â· $dayLabel at $time',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: a.status == AppointmentStatus.confirmed
                    ? AppPalette.successSoft(context)
                    : AppPalette.infoSoft(context),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                a.status.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: a.status == AppointmentStatus.confirmed
                      ? AppColors.success
                      : AppColors.info,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(AppointmentType t) => switch (t) {
        AppointmentType.inPerson => AppIcons.location,
        AppointmentType.virtual => AppIcons.videocam,
        AppointmentType.phone => AppIcons.phone,
      };
}

class _TodayMeds extends StatelessWidget {
  const _TodayMeds({required this.doses});
  final List<MedicationDose> doses;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Today\'s medications',
          icon: AppIcons.medication,
          actionLabel: 'View all',
          onAction: () => Navigator.of(context)
              .pushNamed(RouteNames.patientMedications),
        ),
        Column(
          children: [
            for (var i = 0; i < doses.length; i++) ...[
              if (i > 0) Divider(height: 20, color: AppPalette.border(context)),
              _DoseRow(dose: doses[i]),
            ],
          ],
        ),
      ],
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose});
  final MedicationDose dose;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.jm().format(dose.scheduledAt);
    final isTaken = dose.status == DoseStatus.taken;
    return Row(
      children: [
        Container(
          height: 38,
          width: 38,
          decoration: BoxDecoration(
            color: AppColors.glucoseAmber.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: const Icon(AppIcons.medication,
              color: AppColors.glucoseAmber, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dose.name,
                  style: Theme.of(context).textTheme.titleMedium),
              Text('${dose.dosage} Â· $time',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (isTaken)
          const RiskBadge(risk: RiskLevel.normal, label: 'Taken', dense: true)
        else
          AppButton(
            label: 'Log dose',
            size: AppButtonSize.sm,
            variant: AppButtonVariant.secondary,
            onPressed: () => LogDoseSheet.show(context, dose),
          ),
      ],
    );
  }
}

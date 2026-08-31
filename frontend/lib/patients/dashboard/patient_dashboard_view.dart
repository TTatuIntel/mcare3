import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/auth/auth_state.dart';
import '../../core/location/google_maps_service.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/announcement.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/meal_plan.dart';
import '../../shared/models/medication.dart';
import '../../shared/navigation/notification_router.dart';
import '../../shared/navigation/vital_navigation.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/profile_completion.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/announcements_state.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/state/meal_plans_state.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/state/messages_state.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/state/report_consents_state.dart';
import '../../shared/state/sos_state.dart';
import '../../shared/state/support_state.dart';
import '../../shared/state/vital_report_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_motion.dart';
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
import '../../shared/widgets/patient_sheet.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/section_label.dart';
import '../vitals/submit_vital_sheet.dart';
import '../vitals/vital_preferences_sheet.dart';
import '../medications/log_dose_sheet.dart';

part 'patient_dashboard_home_sections.dart';
part 'patient_dashboard_today_hub.dart';
part 'patient_dashboard_vitals.dart';

/// Tints the home "Log vital" button by the worst tracked reading, so the
/// action the patient reaches for carries the same urgency the board shows.
List<Color> _homeFabColors() {
  var hasCritical = false;
  var hasWarning = false;
  for (final key in VitalsState.instance.tracked) {
    final risk = VitalsState.instance.latestOf(key)?.risk;
    if (risk == RiskLevel.critical) hasCritical = true;
    if (risk == RiskLevel.warning) hasWarning = true;
  }
  if (hasCritical) return [AppColors.critical, AppColors.warning];
  if (hasWarning) return [AppColors.warning, AppColors.brandIndigo];
  return [AppColors.brandIndigo, const Color(0xFF8B5CF6)];
}

class PatientDashboardView extends StatelessWidget {
  const PatientDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);

    return PatientScaffold(
      currentRoute: RouteNames.patientDashboard,
      // Logging a vital is the patient's most repeated task, so home carries
      // the same floating action the Vitals screen does instead of forcing a
      // scroll down to the board.
      floatingActionButton: tier.isHandheld
          ? GlassFloatingButton(
              icon: AppIcons.add,
              label: 'Log vital',
              dynamicColors: _homeFabColors(),
              onPressed: () => SubmitVitalSheet.show(context),
            )
          : null,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          VitalsState.instance,
          AppointmentsState.instance,
          MedicationsState.instance,
          NotificationState.instance,
          ReportConsentsState.instance,
        ]),
        builder: (context, _) {
          final appointments = AppointmentsState.instance.upcoming;
          final doses = MedicationsState.instance.dosesForToday();
          final unread = NotificationState.instance.unreadCount;

          return _PatientHomeLayout(
            appointments: appointments,
            doses: doses,
            unreadNotifications: unread,
            reserveFabSpace: tier.isHandheld,
          );
        },
      ),
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
      items.add(
        _ActivityEntry(
          sortAt: dose.takenAt ?? dose.scheduledAt,
          priority: isPending ? 90 : 35,
          dose: dose,
        ),
      );
    }

    for (final appt in AppointmentsState.instance.upcoming.take(3)) {
      final isToday = DateUtils.isSameDay(appt.scheduledAt, DateTime.now());
      items.add(
        _ActivityEntry(
          sortAt: appt.scheduledAt,
          priority: isToday ? 85 : 70,
          appointment: appt,
        ),
      );
    }

    for (final n in NotificationState.instance.activeItems.take(4)) {
      items.add(
        _ActivityEntry(
          sortAt: n.createdAt,
          priority: n.read ? 25 : 75,
          notification: n,
        ),
      );
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
      separatorBuilder: (_, _) =>
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
            'Log vitals, take medications, or book a visit — activity will show up here.',
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
                color: AppColors.glucoseAmber.withValues(alpha: 0.12),
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
            _FeedStatusChip(label: dose.status.label, color: dose.status.color),
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
    final isToday = DateUtils.isSameDay(
      appointment.scheduledAt,
      DateTime.now(),
    );
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
                color: AppColors.bpPurple.withValues(alpha: 0.12),
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
                    '$dayLabel · $time',
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
                color: accent.withValues(alpha: 0.12),
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
                      fontWeight: notification.read
                          ? FontWeight.w600
                          : FontWeight.w700,
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
        color: color.withValues(alpha: 0.12),
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

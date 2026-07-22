import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/models/appointment.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../../shared/widgets/staff_stat_cards.dart';
import 'doctor_appointment_flows.dart';

class DoctorAppointmentsView extends StatefulWidget {
  const DoctorAppointmentsView({super.key});

  @override
  State<DoctorAppointmentsView> createState() =>
      _DoctorAppointmentsViewState();
}

class _DoctorAppointmentsViewState extends State<DoctorAppointmentsView> {
  DateTime _displayMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
  );
  DateTime? _selectedDay;

  void _prevMonth() => setState(() {
        _displayMonth =
            DateTime(_displayMonth.year, _displayMonth.month - 1);
        _selectedDay = null;
      });

  void _nextMonth() => setState(() {
        _displayMonth =
            DateTime(_displayMonth.year, _displayMonth.month + 1);
        _selectedDay = null;
      });

  void _selectDay(DateTime day) => setState(() {
        _selectedDay = _isSameDay(_selectedDay, day) ? null : day;
      });

  void _clearFilter() => setState(() => _selectedDay = null);

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorAppointments,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Appointments',
      subtitle: 'Schedule, confirm, and manage patient visits',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final all = StaffState.instance.appointmentsForDoctorCaseload()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
          final now = DateTime.now();
          final today = all
              .where((a) => _isSameDay(a.startAt, now) && a.isUpcoming)
              .toList();
          final upcoming = all
              .where(
                  (a) => a.isUpcoming && !_isSameDay(a.startAt, now))
              .toList();
          final accent = Theme.of(context).colorScheme.primary;

          // Days in current display month that have appointments.
          final daysWithAppts = <DateTime>{};
          for (final a in all) {
            final d = DateTime(a.startAt.year, a.startAt.month, a.startAt.day);
            if (a.startAt.year == _displayMonth.year &&
                a.startAt.month == _displayMonth.month) {
              daysWithAppts.add(d);
            }
          }

          // Appointments filtered by selected day (if any).
          final filtered = _selectedDay == null
              ? all
              : all
                  .where((a) => _isSameDay(a.startAt, _selectedDay!))
                  .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Stats ─────────────────────────────────────────────────────
              StaggeredEntry(
                index: 0,
                child: StaffStatCardsGrid(
                  cards: [
                    StaffStatCardData(
                      value: '${today.length}',
                      label: 'Today',
                      detail: today.isEmpty
                          ? 'No visits today'
                          : 'Next ${DateFormat.jm().format(today.first.startAt)}',
                      icon: AppIcons.appointment,
                      accent: today.isNotEmpty
                          ? AppColors.success
                          : AppPalette.textMuted(context),
                    ),
                    StaffStatCardData(
                      value: '${upcoming.length}',
                      label: 'Upcoming',
                      detail: '${all.where((a) => a.isUpcoming).length} active',
                      icon: AppIcons.calendar,
                      accent: accent,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Month calendar ────────────────────────────────────────────
              StaggeredEntry(
                index: 1,
                child: _MonthCalendar(
                  displayMonth: _displayMonth,
                  selectedDay: _selectedDay,
                  daysWithAppointments: daysWithAppts,
                  onPrevMonth: _prevMonth,
                  onNextMonth: _nextMonth,
                  onSelectDay: _selectDay,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Schedule header + CTA ─────────────────────────────────────
              StaggeredEntry(
                index: 2,
                child: Row(
                  children: [
                    Expanded(
                      child: SectionLabel(
                        title: _selectedDay == null
                            ? 'Schedule'
                            : DateFormat('EEE, MMM d').format(_selectedDay!),
                        icon: AppIcons.appointment,
                        trailing: '${filtered.length}',
                        actionLabel: 'New visit',
                        onAction: () =>
                            DoctorAppointmentFlows.openSchedule(context),
                      ),
                    ),
                    if (_selectedDay != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      TextButton.icon(
                        onPressed: _clearFilter,
                        icon: const Icon(AppIcons.close, size: 14),
                        label: const Text('All'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppPalette.textMuted(context),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 3,
                child: GlassCard(
                  frosted: true,
                  onTap: () => DoctorAppointmentFlows.openSchedule(context),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      Icon(AppIcons.add, color: accent, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Schedule appointment with a patient',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(AppIcons.chevronRight,
                          size: 16, color: AppPalette.textMuted(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Appointment list ─────────────────────────────────────────
              if (filtered.isEmpty)
                StaggeredEntry(
                  index: 4,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.appointment,
                      title: _selectedDay == null
                          ? 'Schedule is clear'
                          : 'Nothing on ${DateFormat('MMM d').format(_selectedDay!)}',
                      message: _selectedDay == null
                          ? 'Book a visit with an assigned patient to get started.'
                          : 'No appointments on this day.',
                      compact: true,
                      actionLabel: _selectedDay == null ? 'Schedule visit' : null,
                      onAction: _selectedDay == null
                          ? () => DoctorAppointmentFlows.openSchedule(context)
                          : null,
                    ),
                  ),
                )
              else
                ..._daySections(context, filtered, startIndex: 4),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  static List<Widget> _daySections(
    BuildContext context,
    List<StaffAppointment> all, {
    required int startIndex,
  }) {
    final byDay = <String, List<StaffAppointment>>{};
    for (final a in all) {
      final k = DateFormat.yMMMEd().format(a.startAt);
      byDay.putIfAbsent(k, () => []).add(a);
    }
    final dayEntries = byDay.entries.toList();
    final widgets = <Widget>[];
    for (var i = 0; i < dayEntries.length; i++) {
      widgets.addAll([
        StaggeredEntry(
          index: startIndex + i * 2,
          child: SectionLabel(
            title: dayEntries[i].key,
            icon: AppIcons.calendar,
            trailing: '${dayEntries[i].value.length}',
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        StaggeredEntry(
          index: startIndex + i * 2 + 1,
          child: StaffListCard(
            children: dayEntries[i]
                .value
                .map((a) => _appointmentRow(context, a))
                .toList(),
          ),
        ),
        if (i < dayEntries.length - 1) const SizedBox(height: AppSpacing.lg),
      ]);
    }
    return widgets;
  }

  static Widget _appointmentRow(BuildContext context, StaffAppointment a) {
    return StaffListRow(
      icon: a.type.icon,
      iconColor: a.status.color,
      title: a.patientName,
      subtitle:
          '${DateFormat.jm().format(a.startAt)} · ${a.type.label}${a.reason != null ? ' · ${a.reason}' : ''}',
      pill: a.status.label,
      pillColor: a.status.color,
      onTap: () => DoctorAppointmentFlows.openDetail(context, a.id),
    );
  }

  static bool _isSameDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ---------------------------------------------------------------------------
// Month calendar widget
// ---------------------------------------------------------------------------

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.displayMonth,
    required this.selectedDay,
    required this.daysWithAppointments,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onSelectDay,
  });

  final DateTime displayMonth;
  final DateTime? selectedDay;
  final Set<DateTime> daysWithAppointments;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDay;

  static const _dayLabels = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final primary = theme.colorScheme.primary;

    // First day of displayed month and its weekday offset (0=Sun).
    final firstOfMonth = DateTime(displayMonth.year, displayMonth.month, 1);
    final startOffset = firstOfMonth.weekday % 7; // Mon=1 → offset=1, Sun=0
    final daysInMonth =
        DateUtils.getDaysInMonth(displayMonth.year, displayMonth.month);
    final totalCells = startOffset + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          // Month navigation header
          Row(
            children: [
              IconButton(
                icon: const Icon(AppIcons.chevronLeft, size: 18),
                onPressed: onPrevMonth,
                tooltip: 'Previous month',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
              ),
              Expanded(
                child: Text(
                  DateFormat.yMMMM().format(displayMonth),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(AppIcons.chevronRight, size: 18),
                onPressed: onNextMonth,
                tooltip: 'Next month',
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Day-of-week headers
          Row(
            children: _dayLabels
                .map(
                  (d) => Expanded(
                    child: Text(
                      d,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.xs),

          // Calendar grid
          for (var row = 0; row < rows; row++) ...[
            Row(
              children: List.generate(7, (col) {
                final cellIndex = row * 7 + col;
                final dayNum = cellIndex - startOffset + 1;
                if (dayNum < 1 || dayNum > daysInMonth) {
                  return const Expanded(child: SizedBox());
                }
                final cellDate = DateTime(
                    displayMonth.year, displayMonth.month, dayNum);
                final isToday = cellDate == today;
                final isSelected = selectedDay != null &&
                    cellDate.year == selectedDay!.year &&
                    cellDate.month == selectedDay!.month &&
                    cellDate.day == selectedDay!.day;
                final hasAppt = daysWithAppointments.contains(cellDate);

                return Expanded(
                  child: GestureDetector(
                    onTap: () => onSelectDay(cellDate),
                    child: Container(
                      height: 38,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? primary
                                  : isToday
                                      ? primary.withOpacity(0.12)
                                      : Colors.transparent,
                              border: isToday && !isSelected
                                  ? Border.all(
                                      color: primary.withOpacity(0.4),
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$dayNum',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: isSelected
                                    ? Colors.white
                                    : isToday
                                        ? primary
                                        : theme.textTheme.bodyMedium?.color,
                              ),
                            ),
                          ),
                          if (hasAppt)
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? Colors.white.withOpacity(0.8)
                                    : primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (row < rows - 1) const SizedBox(height: 2),
          ],

          // Legend
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Has appointment',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary.withOpacity(0.12),
                  border: Border.all(
                    color: primary.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'T',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Today',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/appointment.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_floating_button.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/responsive.dart';
import '../../shared/widgets/section_label.dart';
import 'book_appointment_sheet.dart';

class AppointmentsView extends StatefulWidget {
  const AppointmentsView({super.key});

  @override
  State<AppointmentsView> createState() => _AppointmentsViewState();
}

class _AppointmentsViewState extends State<AppointmentsView> {
  _Filter _filter = _Filter.upcoming;

  @override
  Widget build(BuildContext context) {
    final tier = ResponsiveBuilder.of(context);

    return PatientScaffold(
      currentRoute: RouteNames.patientAppointments,
      title: 'Visits',
      subtitle: 'Upcoming visits with your care team',
      floatingActionButton: tier.isHandheld
          ? GlassFloatingButton(
              icon: AppIcons.add,
              label: 'Book visit',
              accent: AppColors.brandIndigo,
              onPressed: () => BookAppointmentSheet.show(context),
            )
          : null,
      body: AnimatedBuilder(
        animation: AppointmentsState.instance,
        builder: (context, _) {
          final s = AppointmentsState.instance;
          final upcoming = s.upcoming;
          final past = s.past;
          final cancelled = s.cancelled;
          final next = upcoming.isEmpty ? null : upcoming.first;
          final items = switch (_filter) {
            _Filter.upcoming => upcoming,
            _Filter.past => past,
            _Filter.cancelled => cancelled,
          };

          final todayStr = DateFormat('EEEE, MMM d').format(DateTime.now());

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: Text(
                  todayStr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 1,
                child: _VisitsHero(
                  upcomingCount: upcoming.length,
                  pastCount: past.length,
                  cancelledCount: cancelled.length,
                  nextVisit: next,
                  onBook: () => BookAppointmentSheet.show(context),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 2,
                child: _VisitsQuickActions(
                  filter: _filter,
                  upcoming: upcoming.length,
                  past: past.length,
                  cancelled: cancelled.length,
                  onBook: () => BookAppointmentSheet.show(context),
                  onSelectFilter: (f) => setState(() => _filter = f),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: switch (_filter) {
                    _Filter.upcoming => 'Upcoming visits',
                    _Filter.past => 'Past visits',
                    _Filter.cancelled => 'Cancelled visits',
                  },
                  icon: AppIcons.appointment,
                  trailing: items.isEmpty ? null : '${items.length}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              StaggeredEntry(
                index: 4,
                child: _VisitsList(
                  items: items,
                  emptyKind: _filter,
                  onBook: () => BookAppointmentSheet.show(context),
                ),
              ),
              SizedBox(height: tier.isHandheld ? 88 : AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

enum _Filter { upcoming, past, cancelled }

class _VisitsHero extends StatelessWidget {
  const _VisitsHero({
    required this.upcomingCount,
    required this.pastCount,
    required this.cancelledCount,
    required this.nextVisit,
    required this.onBook,
  });

  final int upcomingCount;
  final int pastCount;
  final int cancelledCount;
  final Appointment? nextVisit;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSoon = nextVisit != null &&
        nextVisit!.scheduledAt.difference(DateTime.now()).inHours < 48;
    final accent = upcomingCount == 0
        ? AppColors.brandIndigo
        : isSoon
            ? AppColors.warning
            : AppColors.brandIndigo;
    final iconBg = upcomingCount == 0
        ? AppPalette.infoSoft(context)
        : isSoon
            ? AppPalette.warningSoft(context)
            : AppPalette.infoSoft(context);

    final headline = nextVisit == null
        ? 'No upcoming visits'
        : _isToday(nextVisit!.scheduledAt)
            ? 'Visit today'
            : 'Next visit ${DateFormat.MMMd().format(nextVisit!.scheduledAt)}';

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  AppIcons.appointment,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  headline,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppPalette.ink(context),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (nextVisit != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: accent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    nextVisit!.type.icon,
                    size: 14,
                    color: accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${nextVisit!.doctorName} · ${DateFormat.jm().format(nextVisit!.scheduledAt)} · ${nextVisit!.type.label}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.ink(context),
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: AppPalette.border(context)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _HeroStat(label: 'Upcoming', value: '$upcomingCount'),
              _HeroStatDivider(),
              _HeroStat(label: 'Past', value: '$pastCount'),
              _HeroStatDivider(),
              _HeroStat(
                label: 'Cancelled',
                value: '$cancelledCount',
                accent: cancelledCount > 0 ? AppPalette.textMuted(context) : null,
              ),
              _HeroStatDivider(),
              _HeroStat(
                label: 'Book',
                value: '+',
                accent: AppColors.brandIndigo,
                onTap: onBook,
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: accent ?? AppPalette.ink(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return Expanded(child: child);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: child,
        ),
      ),
    );
  }
}

class _HeroStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      width: 1,
      color: AppPalette.border(context),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    );
  }
}

class _VisitsQuickActions extends StatelessWidget {
  const _VisitsQuickActions({
    required this.filter,
    required this.upcoming,
    required this.past,
    required this.cancelled,
    required this.onBook,
    required this.onSelectFilter,
  });

  final _Filter filter;
  final int upcoming;
  final int past;
  final int cancelled;
  final VoidCallback onBook;
  final ValueChanged<_Filter> onSelectFilter;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: AppIcons.add,
              label: 'Book',
              onTap: onBook,
            ),
          ),
          Container(height: 28, width: 1, color: AppPalette.border(context)),
          Expanded(
            child: _QuickAction(
              icon: AppIcons.appointment,
              label: 'Upcoming',
              badge: upcoming > 0 ? '$upcoming' : null,
              selected: filter == _Filter.upcoming,
              onTap: () => onSelectFilter(_Filter.upcoming),
            ),
          ),
          Container(height: 28, width: 1, color: AppPalette.border(context)),
          Expanded(
            child: _QuickAction(
              icon: AppIcons.records,
              label: 'Past',
              badge: past > 0 ? '$past' : null,
              onTap: () => onSelectFilter(_Filter.past),
              selected: filter == _Filter.past,
            ),
          ),
          Container(height: 28, width: 1, color: AppPalette.border(context)),
          Expanded(
            child: _QuickAction(
              icon: AppIcons.alert,
              label: 'Cancelled',
              badge: cancelled > 0 ? '$cancelled' : null,
              onTap: () => onSelectFilter(_Filter.cancelled),
              selected: filter == _Filter.cancelled,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? AppColors.brandIndigo : AppColors.brandIndigo;

    return Material(
      color: selected ? AppColors.brandIndigo.withOpacity(0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? AppColors.brandIndigo : color,
                  ),
                  if (badge != null)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brandIndigo,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text(
                          badge!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? AppColors.brandIndigo : AppPalette.ink(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisitsList extends StatelessWidget {
  const _VisitsList({
    required this.items,
    required this.emptyKind,
    required this.onBook,
  });

  final List<Appointment> items;
  final _Filter emptyKind;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return GlassCard(
        frosted: true,
        child: EmptyStateView(
          icon: AppIcons.appointment,
          title: switch (emptyKind) {
            _Filter.upcoming => 'No upcoming visits',
            _Filter.past => 'No past visits',
            _Filter.cancelled => 'No cancelled visits',
          },
          message: emptyKind == _Filter.upcoming
              ? 'Book a visit with your care team.'
              : 'Your history will appear here.',
          actionLabel: emptyKind == _Filter.upcoming ? 'Book a visit' : null,
          onAction: emptyKind == _Filter.upcoming ? onBook : null,
          compact: true,
        ),
      );
    }

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
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            _VisitRow(appointment: items[i]),
          ],
        ],
      ),
    );
  }
}

class _VisitRow extends StatelessWidget {
  const _VisitRow({required this.appointment});
  final Appointment appointment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = appointment;
    final date = DateFormat.MMMd().format(a.scheduledAt);
    final time = DateFormat.jm().format(a.scheduledAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pushNamed(
          RouteNames.patientAppointmentDetail,
          arguments: a.id,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: a.status.softBg(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: a.status.color.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Container(
                height: 32,
                width: 32,
                decoration: BoxDecoration(
                  color: a.status.color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat.d().format(a.scheduledAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: a.status.color,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        height: 1,
                      ),
                    ),
                    Text(
                      DateFormat.MMM().format(a.scheduledAt).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: a.status.color,
                        fontWeight: FontWeight.w700,
                        fontSize: 8,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.doctorName,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$date · $time · ${a.type.label}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (a.reason != null)
                      Text(
                        a.reason!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: a.status.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  a.status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: a.status.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                AppIcons.chevronRight,
                size: 14,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

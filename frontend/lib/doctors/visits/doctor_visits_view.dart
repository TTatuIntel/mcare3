import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../appointments/doctor_appointment_flows.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
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

/// Today's and near-term patient visits — focused workflow view.
/// Full calendar management lives under [DoctorAppointmentsView].
class DoctorVisitsView extends StatelessWidget {
  const DoctorVisitsView({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorVisits,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Visits',
      subtitle: 'Today and upcoming patient visits',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final assignedIds = StaffState.instance
              .assignedPatientsForDoctor()
              .map((p) => p.id)
              .toSet();
          final mine =
              StaffState.instance.appointments
                  .where(
                    (a) =>
                        a.patientId != null &&
                        assignedIds.contains(a.patientId),
                  )
                  .toList()
                ..sort((a, b) => a.startAt.compareTo(b.startAt));

          final now = DateTime.now();
          final today = mine.where((a) => _isSameDay(a.startAt, now)).toList();
          final upcoming = mine
              .where(
                (a) => a.startAt.isAfter(now) && !_isSameDay(a.startAt, now),
              )
              .take(8)
              .toList();

          if (mine.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaggeredEntry(
                  index: 0,
                  child: GlassCard(
                    frosted: true,
                    child: const EmptyStateView(
                      icon: AppIcons.appointment,
                      title: 'No visits scheduled',
                      message: 'Patient visits will appear here.',
                      compact: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.huge),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: SectionLabel(
                  title: 'Today',
                  icon: AppIcons.appointment,
                  trailing: '${today.length}',
                  actionLabel: 'Schedule',
                  onAction: () => DoctorAppointmentFlows.openSchedule(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 1,
                child: today.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: const EmptyStateView(
                          icon: AppIcons.appointment,
                          title: 'No visits today',
                          message:
                              'Your caseload has no visits booked for today.',
                          compact: true,
                        ),
                      )
                    : StaffListCard(
                        children: today
                            .map(
                              (a) => StaffListRow(
                                icon: a.typeIcon,
                                iconColor: a.statusColor,
                                title: a.patientName,
                                subtitle:
                                    '${DateFormat.jm().format(a.startAt)} · ${a.typeLabel}${a.reason != null ? ' · ${a.reason}' : ''}',
                                pill: a.statusLabel,
                                pillColor: a.statusColor,
                                onTap: () => DoctorAppointmentFlows.openDetail(
                                  context,
                                  a.id,
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: AppSpacing.lg),
              StaggeredEntry(
                index: 2,
                child: SectionLabel(
                  title: 'Coming up',
                  icon: AppIcons.calendar,
                  trailing: '${upcoming.length}',
                  actionLabel: 'Full schedule',
                  onAction: () => Navigator.of(
                    context,
                  ).pushNamed(RouteNames.doctorAppointments),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 3,
                child: upcoming.isEmpty
                    ? GlassCard(
                        frosted: true,
                        child: const EmptyStateView(
                          icon: AppIcons.calendar,
                          title: 'Nothing else this week',
                          message: 'Nothing else on the books this week.',
                          compact: true,
                        ),
                      )
                    : StaffListCard(
                        children: upcoming
                            .map(
                              (a) => StaffListRow(
                                icon: a.typeIcon,
                                iconColor: AppColors.info,
                                title: a.patientName,
                                subtitle:
                                    '${DateFormat.MMMd().add_jm().format(a.startAt)} · ${a.typeLabel}',
                                onTap: () => DoctorAppointmentFlows.openDetail(
                                  context,
                                  a.id,
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

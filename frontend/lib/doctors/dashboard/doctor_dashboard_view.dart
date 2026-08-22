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
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import 'critical_alert_popup.dart';
import 'doctor_activity_feed.dart';

part 'doctor_home_sections.dart';

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
          final alertSummary = StaffState.instance.caseloadAlertSummary(
            patientIds: assignedIds,
          );
          final openAlerts = alertSummary.openCount;
          final criticalAlerts = alertSummary.criticalCount;
          final sosCases = StaffState.instance.patientSos
              .where((e) => assignedIds.contains(e.patientId) && e.isActive)
              .toList();
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
          final activity = DoctorActivityFeed.collect(
            context: context,
            assignedIds: assignedIds,
            patientName: StaffState.instance.patientById,
          );

          final nextVisit = todayAppts.isEmpty ? null : todayAppts.first;

          // Fire critical-alert popup once per unseen critical alert in
          // the doctor's caseload. The popup itself dedupes via its
          // internal `_shownIds` set.
          if (criticalAlerts > 0) {
            CriticalAlertPopup.maybeShow(context);
          }

          return _DoctorHomeLayout(
            assignedCount: assigned.length,
            elevatedCount: elevated,
            openAlerts: openAlerts,
            alertDetail: alertSummary.kpiDetail,
            alertAccent: alertSummary.kpiAccent(),
            todayVisits: todayAppts,
            nextVisit: nextVisit,
            activity: activity,
            sosCases: sosCases,
            onOpenPatients: () =>
                Navigator.of(context).pushNamed(RouteNames.doctorPatients),
            onOpenAlerts: () => openCaseloadAlertPrimary(context, alertSummary),
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

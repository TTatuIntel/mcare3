import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/auth/auth_state.dart';
import '../../core/location/google_maps_service.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/announcement.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/document.dart';
import '../../shared/models/medication.dart';
import '../../shared/navigation/vital_navigation.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/profile_completion.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/support_ticket.dart';
import '../../shared/models/vital.dart';
import '../../shared/models/vital_report_request.dart';
import '../../shared/state/announcements_state.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/state/documents_state.dart';
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
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/section_label.dart';
import '../meals/meal_plan_sheets.dart';
import '../vitals/submit_vital_sheet.dart';
import '../vitals/patient_vital_insights.dart';
import '../vitals/vital_preferences_sheet.dart';
import '../medications/log_dose_sheet.dart';

part 'patient_dashboard_for_you.dart';
part 'patient_dashboard_home_sections.dart';
part 'patient_dashboard_today_hub.dart';
part 'patient_dashboard_vitals.dart';

class PatientDashboardView extends StatelessWidget {
  const PatientDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientDashboard,
      maxContentWidth: 1120,
      floatingActionButton: GlassFloatingButton(
        icon: AppIcons.add,
        label: 'Log vital',
        dynamicColors: const [
          AppColors.brandIndigo,
          AppColors.heartRed,
          AppColors.glucoseAmber,
        ],
        onPressed: () => SubmitVitalSheet.show(context),
      ),
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
          );
        },
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

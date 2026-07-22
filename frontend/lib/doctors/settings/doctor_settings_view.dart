import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/settings/settings_definitions.dart';
import '../../shared/settings/widgets/staff_personal_settings_scaffold.dart';
import '../../shared/theme/app_colors.dart';

/// Doctor settings — shared personal settings scaffold.
class DoctorSettingsView extends StatelessWidget {
  const DoctorSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffPersonalSettingsScaffold(
      currentRoute: RouteNames.doctorSettings,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      notificationRole: SettingsNotificationRole.doctor,
      accent: AppColors.info,
      heroTitle: 'Personalise your workspace',
    );
  }
}

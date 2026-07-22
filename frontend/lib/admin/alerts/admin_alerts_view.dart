import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/staff/staff_alerts_screen.dart';

class AdminAlertsView extends StatelessWidget {
  const AdminAlertsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffAlertsScreen(
      currentRoute: RouteNames.adminAlerts,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
    );
  }
}

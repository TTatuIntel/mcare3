import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/staff_feature_views.dart';

/// Admin notifications inbox — the shared staff notifications view with an
/// admin date header. Refresh, panel, and account shortcuts are all shared.
class AdminNotificationsView extends StatelessWidget {
  const AdminNotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    return StaffNotificationsView(
      currentRoute: RouteNames.adminNotifications,
      destinations: StaffDestinations.admin(),
      profileRoute: RouteNames.adminProfile,
      notificationsRoute: RouteNames.adminNotifications,
      header: const PatientDateHeader(),
    );
  }
}

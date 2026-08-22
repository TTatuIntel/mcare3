import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/staff_hub/staff_hub.dart';

/// Thin role adapter for the shared Guided Operations Hub.
class AdminGuidedOperationsView extends StatelessWidget {
  const AdminGuidedOperationsView({
    super.key,
    this.initialSection = StaffHubSection.home,
    this.currentRoute = RouteNames.adminDashboard,
  });

  final StaffHubSection initialSection;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    return StaffGuidedOperationsHub(
      role: UserRole.admin,
      currentRoute: currentRoute,
      initialSection: initialSection,
    );
  }
}

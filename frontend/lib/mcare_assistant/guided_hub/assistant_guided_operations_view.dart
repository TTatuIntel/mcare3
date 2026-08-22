import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/user_role.dart';
import '../../shared/staff_hub/staff_hub.dart';

/// Thin delegated-role adapter for the shared Guided Operations Hub.
class AssistantGuidedOperationsView extends StatelessWidget {
  const AssistantGuidedOperationsView({
    super.key,
    this.initialSection = StaffHubSection.home,
    this.currentRoute = RouteNames.assistantDashboard,
  });

  final StaffHubSection initialSection;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    return StaffGuidedOperationsHub(
      role: UserRole.mcareAssistant,
      currentRoute: currentRoute,
      initialSection: initialSection,
    );
  }
}

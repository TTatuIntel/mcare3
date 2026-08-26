import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_hub.dart';

/// Patient-facing landing page for personal account and app preferences.
class PatientMoreHubView extends StatelessWidget {
  const PatientMoreHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PatientScaffold(
      currentRoute: RouteNames.patientMore,
      title: 'More',
      subtitle: 'Notifications, profile and preferences',
      maxContentWidth: 1080,
      body: SectionHub(
        title: 'Account and preferences',
        description:
            'Review your updates, maintain your health profile and personalise mCare.',
        groups: [
          AppSectionGroup(
            title: 'Your account',
            description:
                'Personal information, alerts and application options.',
            links: [
              AppSectionLink(
                title: 'Notifications',
                description:
                    'Read reminders, alerts and updates from your care team.',
                icon: AppIcons.notifications,
                route: RouteNames.patientNotifications,
                color: AppColors.brandIndigo,
              ),
              AppSectionLink(
                title: 'Profile',
                description:
                    'Update personal details, monitoring and emergency contacts.',
                icon: AppIcons.profile,
                route: RouteNames.patientProfile,
                color: AppColors.doctorGreen,
              ),
              AppSectionLink(
                title: 'Settings',
                description:
                    'Manage appearance, language, notifications and privacy.',
                icon: AppIcons.settings,
                route: RouteNames.patientSettings,
                color: AppColors.bpPurple,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

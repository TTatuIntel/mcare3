import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/patient_nav_badges.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_hub.dart';

/// Patient-facing landing page for personal account and app preferences.
class PatientMoreHubView extends StatelessWidget {
  const PatientMoreHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PatientNavBadges.listenable,
      builder: (context, _) => PatientScaffold(
        currentRoute: RouteNames.patientMore,
        title: 'More',
        subtitle: 'Notifications, profile and preferences',
        maxContentWidth: 1080,
        body: SectionHub(
          title: 'Account and preferences',
          description:
              'Review your updates, maintain your health profile and '
              'personalise mCare.',
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
                  badge: PatientNavBadges.inbox,
                ),
                AppSectionLink(
                  title: 'Sharing requests',
                  description:
                      'Approve or decline what mCare may share from your '
                      'record.',
                  icon: AppIcons.check,
                  route: RouteNames.patientReportConsents,
                  color: AppColors.warning,
                  badge: PatientNavBadges.sharingRequests,
                ),
                const AppSectionLink(
                  title: 'Profile',
                  description:
                      'Update personal details, monitoring and emergency '
                      'contacts.',
                  icon: AppIcons.profile,
                  route: RouteNames.patientProfile,
                  color: AppColors.doctorGreen,
                ),
                const AppSectionLink(
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
      ),
    );
  }
}

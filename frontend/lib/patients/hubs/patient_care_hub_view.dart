import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_hub.dart';

/// Patient-facing landing page for visits, conversations, and care support.
class PatientCareHubView extends StatelessWidget {
  const PatientCareHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PatientScaffold(
      currentRoute: RouteNames.patientCare,
      title: 'Care',
      subtitle: 'Visits, messages and your care team',
      maxContentWidth: 1080,
      body: SectionHub(
        title: 'Your care',
        description:
            'Stay connected with your providers and get help when you need it.',
        groups: [
          AppSectionGroup(
            title: 'Connected care',
            description: 'Plan visits and keep in touch with your providers.',
            links: [
              AppSectionLink(
                title: 'Visits',
                description:
                    'Review upcoming appointments or book your next visit.',
                icon: AppIcons.appointment,
                route: RouteNames.patientAppointments,
                color: AppColors.bpPurple,
              ),
              AppSectionLink(
                title: 'Messages',
                description:
                    'Continue secure conversations with your care team.',
                icon: AppIcons.chat,
                route: RouteNames.patientMessages,
                color: AppColors.brandIndigo,
              ),
              AppSectionLink(
                title: 'My care team',
                description:
                    'See assigned providers and request additional care.',
                icon: AppIcons.careTeam,
                route: RouteNames.patientCareTeam,
                color: AppColors.doctorGreen,
              ),
            ],
          ),
          AppSectionGroup(
            title: 'Help and safety',
            description: 'Get support or alert your trusted contacts quickly.',
            links: [
              AppSectionLink(
                title: 'Support',
                description:
                    'Create a support request and follow previous tickets.',
                icon: AppIcons.support,
                route: RouteNames.patientSupport,
                color: AppColors.info,
              ),
              AppSectionLink(
                title: 'Emergency SOS',
                description:
                    'Notify emergency contacts and your care team immediately.',
                icon: AppIcons.sos,
                route: RouteNames.patientSos,
                color: AppColors.critical,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

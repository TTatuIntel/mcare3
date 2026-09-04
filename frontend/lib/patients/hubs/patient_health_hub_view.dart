import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/patient_nav_badges.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_hub.dart';

/// Patient-facing landing page for monitoring, medicines, and records.
class PatientHealthHubView extends StatelessWidget {
  const PatientHealthHubView({super.key});

  @override
  Widget build(BuildContext context) {
    // A hub is the tab's contents, so it reads the same live stores the tab
    // badge does: open it with three doses waiting and the Medications tile
    // says three, and it drops to nothing the moment they are logged.
    return AnimatedBuilder(
      animation: PatientNavBadges.listenable,
      builder: (context, _) => PatientScaffold(
        currentRoute: RouteNames.patientHealth,
        title: 'Health',
        subtitle: 'Vitals, medications and health records',
        maxContentWidth: 1080,
        body: SectionHub(
          title: 'Your health',
          description:
              'Record new readings, follow your medication plan and keep '
              'important documents together.',
          groups: [
            AppSectionGroup(
              title: 'Monitor and manage',
              description: 'The tools you use to manage your health each day.',
              links: [
                const AppSectionLink(
                  title: 'Vitals',
                  description:
                      'Record readings and review trends, ranges and alerts.',
                  icon: AppIcons.vitals,
                  route: RouteNames.patientVitals,
                  color: AppColors.brandIndigo,
                ),
                AppSectionLink(
                  title: 'Medications',
                  description:
                      "View today's doses, prescriptions and medication "
                      'history.',
                  icon: AppIcons.medication,
                  route: RouteNames.patientMedications,
                  color: AppColors.glucoseAmber,
                  badge: PatientNavBadges.health,
                ),
                const AppSectionLink(
                  title: 'Documents',
                  description:
                      'Open lab results, prescriptions, imaging and reports.',
                  icon: AppIcons.document,
                  route: RouteNames.patientDocuments,
                  color: AppColors.bpPurple,
                ),
                const AppSectionLink(
                  title: 'Meals',
                  description: 'Review meal plans assigned by your care team.',
                  icon: AppIcons.meals,
                  route: RouteNames.patientMeals,
                  color: AppColors.success,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

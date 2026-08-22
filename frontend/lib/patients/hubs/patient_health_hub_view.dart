import 'package:flutter/material.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_hub.dart';

/// Patient-facing landing page for monitoring, medicines, and records.
class PatientHealthHubView extends StatelessWidget {
  const PatientHealthHubView({super.key});

  @override
  Widget build(BuildContext context) {
    return const PatientScaffold(
      currentRoute: RouteNames.patientHealth,
      title: 'Health',
      subtitle: 'Vitals, medications and health records',
      maxContentWidth: 1080,
      body: SectionHub(
        title: 'Your health',
        description:
            'Record new readings, follow your medication plan and keep important documents together.',
        groups: [
          AppSectionGroup(
            title: 'Monitor and manage',
            description: 'The tools you use to manage your health each day.',
            links: [
              AppSectionLink(
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
                    'View today\'s doses, prescriptions and medication history.',
                icon: AppIcons.medication,
                route: RouteNames.patientMedications,
                color: AppColors.glucoseAmber,
              ),
              AppSectionLink(
                title: 'Documents',
                description:
                    'Open lab results, prescriptions, imaging and reports.',
                icon: AppIcons.document,
                route: RouteNames.patientDocuments,
                color: AppColors.bpPurple,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

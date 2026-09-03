import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import '../widgets/doctor_rx_sheet.dart';

class DoctorPrescriptionsView extends StatelessWidget {
  const DoctorPrescriptionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorPrescriptions,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Prescriptions',
      subtitle: 'Open a patient workspace to prescribe in context',
      headerActions: [
        AppButton(
          label: 'New',
          icon: AppIcons.add,
          size: AppButtonSize.sm,
          onPressed: () => showDoctorPrescriptionSheet(context),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final assignedIds = StaffState.instance
              .assignedPatientsForDoctor()
              .map((p) => p.id)
              .toSet();
          final rx = StaffState.instance.prescriptions
              .where(
                (p) =>
                    assignedIds.contains(p.patientId) ||
                    p.patientId == 'pending',
              )
              .toList();
          if (rx.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaggeredEntry(
                  index: 0,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.prescription,
                      title: 'No prescriptions yet',
                      actionLabel: 'Issue prescription',
                      onAction: () => showDoctorPrescriptionSheet(context),
                      compact: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.huge),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: SectionLabel(
                  title: 'All prescriptions',
                  icon: AppIcons.prescription,
                  trailing: '${rx.length}',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              StaggeredEntry(
                index: 1,
                child: StaffListCard(
                  children: rx
                      .map(
                        (p) => StaffListRow(
                          icon: AppIcons.prescription,
                          iconColor: AppColors.brandIndigo,
                          title: '${p.drug} ${p.dosage}',
                          subtitle:
                              '${p.patientName} · ${p.frequency} · ${DateFormat.MMMd().format(p.issuedAt)}',
                          pill: p.status,
                          pillColor: AppColors.success,
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }
}

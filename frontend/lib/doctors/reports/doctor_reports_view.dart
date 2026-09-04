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
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';
import 'doctor_report_signatures_view.dart';

class DoctorReportsView extends StatelessWidget {
  const DoctorReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorReports,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Clinical reports',
      subtitle: 'Drafts and published summaries',
      headerActions: [
        AppButton(
          label: 'New',
          icon: AppIcons.add,
          size: AppButtonSize.sm,
          onPressed: () =>
              Navigator.of(context).pushNamed(RouteNames.doctorReportEditor),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final reports = StaffState.instance.reports;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sign-off queue comes first — it is other people's blocked
              // work, so it outranks this doctor's own drafts.
              const StaggeredEntry(
                index: 0,
                child: DoctorReportSignaturesList(),
              ),
              const SizedBox(height: AppSpacing.md),
              StaggeredEntry(
                index: 1,
                child: SectionLabel(
                  title: 'All reports',
                  icon: AppIcons.report,
                  trailing: '${reports.length}',
                ),
              ),
              if (reports.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                StaggeredEntry(
                  index: 1,
                  child: StaffListCard(
                    children: reports
                        .map(
                          (r) => StaffListRow(
                            icon: AppIcons.report,
                            iconColor: AppColors.doctorGreen,
                            title: r.title,
                            subtitle:
                                '${r.patientName} · ${DateFormat.MMMd().format(r.createdAt)}',
                            pill: r.published ? 'Published' : 'Draft',
                            pillColor: r.published
                                ? AppColors.success
                                : AppColors.warning,
                            onTap: () => Navigator.of(context).pushNamed(
                              RouteNames.doctorReportEditor,
                              arguments: r.id,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

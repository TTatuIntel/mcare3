import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/role_shell.dart';
import '../../shared/widgets/section_label.dart';
import '../../shared/widgets/staff_blocks.dart';

class DoctorAlertsView extends StatelessWidget {
  const DoctorAlertsView({super.key});

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      currentRoute: RouteNames.doctorAlerts,
      destinations: StaffDestinations.doctor(),
      profileRoute: RouteNames.doctorProfile,
      notificationsRoute: RouteNames.doctorNotifications,
      title: 'Alerts',
      subtitle: 'Critical and warning vitals across your caseload',
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          final assignedIds = StaffState.instance
              .assignedPatientsForDoctor()
              .map((p) => p.id)
              .toSet();
          final alerts = StaffState.instance.alerts
              .where((a) => assignedIds.contains(a.patientId))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final open =
              alerts.where((a) => !a.resolved).toList(growable: false);
          final resolved =
              alerts.where((a) => a.resolved).toList(growable: false);

          if (alerts.isEmpty) {
            return const EmptyStateView(
              icon: AppIcons.alert,
              title: 'No alerts yet',
              message: 'Patient vital alerts will appear here.',
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (open.isNotEmpty) ...[
                SectionLabel(
                  title: 'Open',
                  trailing: '${open.length} need attention',
                ),
                const SizedBox(height: AppSpacing.sm),
                ...open.asMap().entries.map(
                  (entry) => StaggeredEntry(
                    index: entry.key,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _AlertRow(alert: entry.value),
                    ),
                  ),
                ),
              ],
              if (resolved.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                SectionLabel(
                  title: 'Resolved',
                  trailing: '${resolved.length} recently closed',
                ),
                const SizedBox(height: AppSpacing.sm),
                ...resolved.take(12).toList().asMap().entries.map(
                  (entry) => StaggeredEntry(
                    index: entry.key + open.length,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _AlertRow(alert: entry.value, dimmed: true),
                    ),
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

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, this.dimmed = false});
  final StaffAlert alert;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: EdgeInsets.zero,
      child: StaffListRow(
        icon: alert.vital.icon,
        iconColor: dimmed ? AppPalette.textMuted(context) : alert.severity.color,
        title: '${alert.patientName} · ${alert.vital.label}',
        subtitle:
            '${alert.value} · ${DateFormat.MMMd().add_jm().format(alert.createdAt)}',
        pill: alert.resolved
            ? 'Resolved'
            : (alert.acknowledged ? 'Ack' : alert.severity.label),
        pillColor:
            alert.resolved ? AppColors.success : alert.severity.color,
        onTap: () => Navigator.of(context).pushNamed(
          RouteNames.doctorAlertDetail,
          arguments: alert.id,
        ),
      ),
    );
  }
}

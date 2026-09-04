import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/navigation/staff_destinations.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/risk_badge.dart';
import '../../shared/widgets/role_shell.dart';
import '../alerts/doctor_alert_resolve_sheet.dart';
import '../patients/doctor_patient_section.dart';

class DoctorAlertDetailView extends StatelessWidget {
  const DoctorAlertDetailView({super.key, required this.alertId});
  final String alertId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: StaffState.instance,
      builder: (context, _) {
        StaffAlert? found;
        for (final a in StaffState.instance.alerts) {
          if (a.id == alertId) {
            found = a;
            break;
          }
        }
        if (found == null) {
          return RoleShell(
            currentRoute: RouteNames.doctorAlerts,
            destinations: StaffDestinations.doctor(),
            profileRoute: RouteNames.doctorProfile,
            notificationsRoute: RouteNames.doctorNotifications,
            title: 'Alert',
            body: GlassCard(
              frosted: true,
              child: EmptyStateView(
                icon: AppIcons.alert,
                title: 'Alert not found',
                compact: true,
              ),
            ),
          );
        }
        final alert = found;
        return RoleShell(
          currentRoute: RouteNames.doctorAlerts,
          destinations: StaffDestinations.doctor(),
          profileRoute: RouteNames.doctorProfile,
          notificationsRoute: RouteNames.doctorNotifications,
          title: '${alert.vital.label} alert',
          subtitle: alert.patientName,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassCard(
                frosted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: alert.severity.color.withOpacity(0.14),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radiusMd),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            alert.vital.icon,
                            color: alert.severity.color,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.value,
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              RiskBadge(risk: alert.severity, dense: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Reported ${DateFormat.MMMd().add_jm().format(alert.createdAt)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                    ),
                    if (alert.resolved &&
                        (alert.resolutionAction != null ||
                            (alert.resolutionNote?.isNotEmpty ?? false))) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppPalette.successSoft(context),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resolution',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                            ),
                            if (alert.resolutionAction != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                formatAlertResolutionAction(alert),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                            if (alert.resolutionNote?.isNotEmpty ?? false) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                alert.resolutionNote!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppPalette.textMuted(context)),
                              ),
                            ],
                            if (alert.resolvedBy?.isNotEmpty ?? false) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'Closed by ${alert.resolvedBy}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppPalette.textMuted(context),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                frosted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppButton(
                      label: alert.acknowledged ? 'Acknowledged' : 'Acknowledge',
                      icon: AppIcons.check,
                      variant: alert.acknowledged
                          ? AppButtonVariant.secondary
                          : AppButtonVariant.primary,
                      onPressed: alert.acknowledged
                          ? null
                          : () async {
                              final ok = await StaffState.instance
                                  .acknowledgeAlert(alert.id);
                              if (!context.mounted) return;
                              if (ok) {
                                AppToast.success(
                                    context, 'Alert acknowledged.');
                              } else {
                                AppToast.warn(
                                    context, 'Could not acknowledge alert.');
                              }
                            },
                    ),
                    if (!alert.resolved) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: 'Resolve alert',
                        icon: AppIcons.check,
                        variant: AppButtonVariant.primary,
                        onPressed: () async {
                          final ok = await DoctorAlertResolveFlow.resolve(
                            context,
                            alert,
                          );
                          if (ok && context.mounted) {
                            Navigator.of(context).maybePop();
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Open patient workspace',
                      icon: AppIcons.chart,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => Navigator.of(context).pushNamed(
                        RouteNames.doctorPatientChart,
                        arguments: {
                          'patientId': alert.patientId,
                          'section': DoctorPatientSection.alerts.name,
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppButton(
                      label: 'Message patient',
                      icon: AppIcons.chat,
                      variant: AppButtonVariant.ghost,
                      onPressed: () => Navigator.of(context)
                          .pushNamed(RouteNames.doctorMessages),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

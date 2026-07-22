import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/notification_item.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/vital_navigation.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';
import '../../shared/widgets/risk_badge.dart';
import 'submit_vital_sheet.dart';

class VitalReadingSheet {
  VitalReadingSheet._();

  static Future<void> show(
    BuildContext context, {
    required VitalReading reading,
  }) {
    return GlassSheet.show(
      context,
      title: reading.vital.label,
      subtitle: 'Reading details · alerts · resolution',
      child: _Body(reading: reading),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.reading});

  final VitalReading reading;

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _rangeLabel(VitalKey vital) {
    final range = VitalRanges.defaults[vital];
    if (range == null) return '—';
    return '${range.normalMin.toStringAsFixed(vital == VitalKey.temperature ? 1 : 0)}–'
        '${range.normalMax.toStringAsFixed(vital == VitalKey.temperature ? 1 : 0)} ${vital.unit}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vital = reading.vital;
    final accent = vital.accent;
    final assigned = VitalsState.instance.isAssigned(vital);

    return AnimatedBuilder(
      animation: NotificationState.instance,
      builder: (context, _) {
        final alert = NotificationState.instance.vitalAlertFor(vital);
        final resolved = NotificationState.instance.resolvedVitalAlertFor(vital);
        final isResolved =
            alert == null &&
            resolved != null &&
            reading.risk == RiskLevel.normal;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: accent.withOpacity(0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(vital.icon, color: accent, size: 24),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: reading.formatValue(),
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text: ' ${vital.unit}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppPalette.textMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat.MMMEd().add_jm().format(reading.recordedAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                        ),
                        Text(
                          'Logged ${_relative(reading.recordedAt)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.textFaint(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RiskBadge(risk: reading.risk, dense: true),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(
              icon: AppIcons.trend,
              label: 'Your normal range',
              value: _rangeLabel(vital),
            ),
            if (assigned) ...[
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(
                icon: AppIcons.lock,
                label: 'Tracking',
                value: 'Care team assigned',
                valueColor: AppColors.brandIndigo,
              ),
            ],
            if (alert != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _AlertCard(
                title: 'Active alert',
                notification: alert,
                tint: AppColors.critical,
                icon: AppIcons.alert,
              ),
            ],
            if (resolved != null) ...[
              const SizedBox(height: AppSpacing.md),
              _AlertCard(
                title: isResolved ? 'Resolved' : 'Previous resolution',
                notification: resolved,
                tint: AppColors.success,
                icon: AppIcons.check,
                resolvedAt: resolved.resolvedAt,
              ),
            ],
            if (alert == null && resolved == null && reading.risk == RiskLevel.normal) ...[
              const SizedBox(height: AppSpacing.lg),
              _StatusBanner(
                icon: AppIcons.check,
                color: AppColors.success,
                message: 'Within your normal range — no alert needed.',
              ),
            ],
            if (reading.note != null && reading.note!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _InfoRow(
                icon: AppIcons.edit,
                label: 'Note',
                value: reading.note!,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (alert != null)
              AppButton(
                label: 'Resolve alert',
                icon: AppIcons.check,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: () {
                  NotificationState.instance.resolve(alert.id);
                  AppToast.success(context, 'Alert resolved.');
                },
              ),
            if (alert != null) const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'View trends & history',
              icon: AppIcons.trend,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                openVitalDetail(context, vital);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Log new reading',
              icon: AppIcons.add,
              variant: AppButtonVariant.ghost,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                SubmitVitalSheet.show(context, initial: vital);
              },
            ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppPalette.textMuted(context)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: valueColor ?? AppPalette.ink(context),
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.title,
    required this.notification,
    required this.tint,
    required this.icon,
    this.resolvedAt,
  });

  final String title;
  final AppNotification notification;
  final Color tint;
  final IconData icon;
  final DateTime? resolvedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: tint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: tint.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: tint),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tint,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            notification.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            notification.body,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
              height: 1.35,
            ),
          ),
          if (resolvedAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Cleared ${DateFormat.MMMd().add_jm().format(resolvedAt!)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: tint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

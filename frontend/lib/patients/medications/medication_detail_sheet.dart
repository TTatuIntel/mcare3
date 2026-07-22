import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/medication.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'dose_detail_sheet.dart';

class MedicationDetailSheet {
  MedicationDetailSheet._();

  static Future<void> show(BuildContext context, Medication med) {
    return GlassSheet.show(
      context,
      title: med.name,
      subtitle: '${med.dosage} · ${med.frequency}',
      child: _Body(med: med),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.med});
  final Medication med;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alert = med.alert;
    final todayDoses = MedicationsState.instance
        .dosesForToday()
        .where((d) => d.medicationId == med.id)
        .toList();

    return AnimatedBuilder(
      animation: MedicationsState.instance,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.glucoseAmber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.glucoseAmber.withOpacity(0.22),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: AppColors.glucoseAmber.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      AppIcons.medication,
                      color: AppColors.glucoseAmber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          med.dosage,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          med.frequency,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AppPalette.textMuted(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _SourceChip(source: med.source),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoRow(label: 'Prescribed by', value: med.prescribedBy),
            _InfoRow(label: 'Form', value: med.form),
            if (med.instructions != null)
              _InfoRow(label: 'Instructions', value: med.instructions!),
            if (med.refillsLeft != null)
              _InfoRow(label: 'Refills left', value: '${med.refillsLeft}'),
            if (med.expiryDate != null)
              _InfoRow(
                label: 'Expires',
                value: DateFormat.yMMMd().format(med.expiryDate!),
              ),
            _InfoRow(
              label: 'Started',
              value: DateFormat.yMMMd().format(med.startDate),
            ),
            if (alert != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: alert.tint.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: alert.tint.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.alert, size: 16, color: alert.tint),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          alert.title,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: alert.tint,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (todayDoses.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Today\'s doses',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final d in todayDoses)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => DoseDetailSheet.show(context, d),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              d.status == DoseStatus.taken
                                  ? AppIcons.check
                                  : AppIcons.time,
                              size: 14,
                              color: d.status.color,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '${DateFormat.jm().format(d.scheduledAt)} · ${d.status.label}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              AppIcons.chevronRight,
                              size: 12,
                              color: AppPalette.textMuted(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Full history',
              icon: AppIcons.records,
              expand: true,
              variant: AppButtonVariant.secondary,
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(
                  RouteNames.patientMedicationDetail,
                  arguments: med.id,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});
  final MedicationSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: source.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: source.color.withOpacity(0.28)),
      ),
      child: Text(
        source.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: source.color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

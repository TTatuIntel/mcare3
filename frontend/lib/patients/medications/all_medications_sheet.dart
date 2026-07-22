import 'package:flutter/material.dart';

import '../../shared/models/medication.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'add_medication_sheet.dart';
import 'medication_detail_sheet.dart';

class AllMedicationsSheet {
  AllMedicationsSheet._();

  static Future<void> show(BuildContext context) {
    return GlassSheet.show(
      context,
      title: 'All medications',
      subtitle: 'Prescriptions and meds you track',
      child: const _Body(),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MedicationsState.instance,
      builder: (context, _) {
        final state = MedicationsState.instance;
        final prescribed = state.prescribed;
        final patientAdded = state.patientAdded;
        final alerts = state.medicationAlerts();

        if (prescribed.isEmpty && patientAdded.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmptyStateView(
                icon: AppIcons.medication,
                title: 'No medications yet',
                message:
                    'Doctor prescriptions and meds you add yourself appear here.',
                actionLabel: 'Add medication',
                onAction: () {
                  Navigator.of(context).pop();
                  AddMedicationSheet.show(context);
                },
                compact: true,
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryStrip(
              total: state.active.length,
              prescribed: prescribed.length,
              yours: patientAdded.length,
              alerts: alerts.length,
            ),
            const SizedBox(height: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MedGroup(
                  title: 'Doctor prescribed',
                  icon: AppIcons.lock,
                  meds: prescribed,
                ),
                if (prescribed.isNotEmpty && patientAdded.isNotEmpty)
                  const SizedBox(height: AppSpacing.lg),
                _MedGroup(
                  title: 'Your medications',
                  icon: AppIcons.add,
                  meds: patientAdded,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Add medication',
              icon: AppIcons.add,
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                AddMedicationSheet.show(context);
              },
            ),
          ],
        );
      },
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.total,
    required this.prescribed,
    required this.yours,
    required this.alerts,
  });

  final int total;
  final int prescribed;
  final int yours;
  final int alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandIndigo.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.brandIndigo.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          _SummaryChip(
            value: '$total',
            label: 'Active',
            accent: AppColors.brandIndigo,
          ),
          _SummaryDivider(),
          _SummaryChip(
            value: '$prescribed',
            label: 'Prescribed',
          ),
          _SummaryDivider(),
          _SummaryChip(
            value: '$yours',
            label: 'Yours',
          ),
          if (alerts > 0) ...[
            _SummaryDivider(),
            _SummaryChip(
              value: '$alerts',
              label: 'Alerts',
              accent: AppColors.warning,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.value,
    required this.label,
    this.accent,
  });

  final String value;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              color: accent ?? AppPalette.ink(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textMuted(context),
              fontWeight: FontWeight.w600,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      width: 1,
      color: AppPalette.border(context),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
    );
  }
}

class _MedGroup extends StatelessWidget {
  const _MedGroup({
    required this.title,
    required this.icon,
    required this.meds,
  });

  final String title;
  final IconData icon;
  final List<Medication> meds;

  @override
  Widget build(BuildContext context) {
    if (meds.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppPalette.textMuted(context)),
            const SizedBox(width: AppSpacing.sm),
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppPalette.surfaceMuted(context).withOpacity(0.5),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                '${meds.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textFaint(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < meds.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.xs),
          _MedTile(med: meds[i]),
        ],
      ],
    );
  }
}

class _MedTile extends StatelessWidget {
  const _MedTile({required this.med});
  final Medication med;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alert = med.alert;
    final todayDoses = MedicationsState.instance
        .dosesForToday()
        .where((d) => d.medicationId == med.id)
        .toList();
    final pending = todayDoses.where((d) => d.status == DoseStatus.pending).length;
    final missed = todayDoses.where((d) => d.status == DoseStatus.missed).length;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          MedicationDetailSheet.show(context, med);
        },
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: alert != null
                ? alert.tint.withOpacity(0.07)
                : AppPalette.surfaceAlt(context).withOpacity(0.5),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: alert != null
                  ? alert.tint.withOpacity(0.28)
                  : AppPalette.border(context),
            ),
          ),
          child: Row(
            children: [
              Container(
                height: 36,
                width: 36,
                decoration: BoxDecoration(
                  color: AppColors.glucoseAmber.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  AppIcons.medication,
                  color: AppColors.glucoseAmber,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            med.name,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _SourceBadge(source: med.source),
                      ],
                    ),
                    Text(
                      '${med.dosage} · ${med.frequency}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (alert != null || pending > 0 || missed > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            if (alert != null)
                              _StatusChip(
                                label: alert.kind == MedicationAlertKind.refillLow
                                    ? 'Refill'
                                    : alert.kind == MedicationAlertKind.expiringSoon
                                        ? 'Expiring'
                                        : 'Expired',
                                color: alert.tint,
                              ),
                            if (pending > 0)
                              _StatusChip(
                                label: '$pending pending',
                                color: AppColors.info,
                              ),
                            if (missed > 0)
                              _StatusChip(
                                label: '$missed missed',
                                color: AppColors.critical,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                AppIcons.chevronRight,
                size: 14,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 8,
            ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final MedicationSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: source.color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: source.color.withOpacity(0.22)),
      ),
      child: Text(
        source.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: source.color,
              fontWeight: FontWeight.w700,
              fontSize: 9,
            ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/medication.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'medication_detail_sheet.dart';

class DoseDetailSheet {
  DoseDetailSheet._();

  static Future<void> show(BuildContext context, MedicationDose dose) {
    return GlassSheet.show(
      context,
      title: dose.name,
      subtitle: '${dose.dosage} · ${DateFormat.jm().format(dose.scheduledAt)}',
      child: _Body(dose: dose),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({required this.dose});
  final MedicationDose dose;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late DoseStatus _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _status = widget.dose.status;
  }

  Medication? get _med =>
      MedicationsState.instance.byId(widget.dose.medicationId);

  Future<void> _applyStatus(DoseStatus status) async {
    setState(() {
      _status = status;
      _saving = true;
    });
    try {
      await MedicationsState.instance.recordDoseRemote(widget.dose.id, status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not update: $e');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(
      context,
      '${widget.dose.name} marked ${status.label.toLowerCase()}.',
    );
  }

  void _requestRefill() {
    Navigator.of(context).pop();
    AppToast.success(context, 'Refill request sent for ${widget.dose.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final med = _med;
    final alert = med?.alert;

    return AnimatedBuilder(
      animation: MedicationsState.instance,
      builder: (context, _) {
        final current = MedicationsState.instance.doses.firstWhere(
          (d) => d.id == widget.dose.id,
          orElse: () => widget.dose,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: current.status.color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: current.status.color.withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: AppColors.glucoseAmber.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: const Icon(
                      AppIcons.medication,
                      color: AppColors.glucoseAmber,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat.MMMEd().add_jm().format(
                            current.scheduledAt,
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Current: ${current.status.label}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: current.status.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(status: current.status),
                ],
              ),
            ),
            if (widget.dose.instructions != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppPalette.infoSoft(context),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(AppIcons.info, size: 14, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        widget.dose.instructions!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (med != null) ...[
              const SizedBox(height: AppSpacing.md),
              _InfoRow(label: 'Frequency', value: med.frequency),
              if (med.refillsLeft != null)
                _InfoRow(label: 'Refills left', value: '${med.refillsLeft}'),
              if (med.expiryDate != null)
                _InfoRow(
                  label: 'Expires',
                  value: DateFormat.yMMMd().format(med.expiryDate!),
                ),
            ],
            if (alert != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: alert.tint.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: alert.tint.withOpacity(0.28)),
                ),
                child: Row(
                  children: [
                    Icon(AppIcons.alert, size: 14, color: alert.tint),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        alert.body,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: alert.tint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Update dose status',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _StatusAction(
                  status: DoseStatus.taken,
                  selected: _status == DoseStatus.taken,
                  onTap: _saving ? null : () => _applyStatus(DoseStatus.taken),
                ),
                _StatusAction(
                  status: DoseStatus.skipped,
                  selected: _status == DoseStatus.skipped,
                  onTap: _saving
                      ? null
                      : () => _applyStatus(DoseStatus.skipped),
                ),
                _StatusAction(
                  status: DoseStatus.missed,
                  selected: _status == DoseStatus.missed,
                  onTap: _saving ? null : () => _applyStatus(DoseStatus.missed),
                ),
                _StatusAction(
                  status: DoseStatus.pending,
                  selected: _status == DoseStatus.pending,
                  onTap: _saving
                      ? null
                      : () => _applyStatus(DoseStatus.pending),
                ),
                if (med != null &&
                    (med.isRefillLow ||
                        alert?.kind == MedicationAlertKind.refillLow ||
                        alert?.kind == MedicationAlertKind.expiringSoon ||
                        alert?.kind == MedicationAlertKind.expired))
                  _RefillAction(onTap: _requestRefill),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (med != null &&
                (med.isRefillLow || med.refillsLeft != null)) ...[
              AppButton(
                label: med.isRefillLow
                    ? 'Request refill now'
                    : 'Request refill',
                icon: AppIcons.report,
                variant: AppButtonVariant.secondary,
                expand: true,
                onPressed: _requestRefill,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (med != null)
              AppButton(
                label: 'Medication details',
                icon: AppIcons.medication,
                variant: AppButtonVariant.ghost,
                expand: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  MedicationDetailSheet.show(context, med);
                },
              ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Full history',
              icon: AppIcons.records,
              variant: AppButtonVariant.ghost,
              expand: true,
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(
                  RouteNames.patientMedicationDetail,
                  arguments: widget.dose.medicationId,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final DoseStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: status.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: status.color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final DoseStatus status;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 148,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? status.color.withOpacity(0.14)
                : AppPalette.surfaceMuted(context).withOpacity(0.4),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected ? status.color : AppPalette.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(_statusIcon(status), size: 16, color: status.color),
              const SizedBox(width: AppSpacing.sm),
              Text(
                status.label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(DoseStatus s) => switch (s) {
    DoseStatus.taken => AppIcons.check,
    DoseStatus.skipped => AppIcons.alert,
    DoseStatus.missed => AppIcons.alert,
    DoseStatus.pending => AppIcons.time,
  };
}

class _RefillAction extends StatelessWidget {
  const _RefillAction({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          width: 148,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppPalette.warningSoft(context).withOpacity(0.6),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.warning.withOpacity(0.45)),
          ),
          child: Row(
            children: [
              const Icon(AppIcons.report, size: 16, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Refill',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/medication.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_label.dart';
import 'dose_detail_sheet.dart';
import 'medication_detail_sheet.dart';

class MedicationDetailView extends StatelessWidget {
  const MedicationDetailView({super.key, required this.medicationId});
  final String medicationId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MedicationsState.instance,
      builder: (context, _) {
        final med = MedicationsState.instance.byId(medicationId);
        if (med == null) {
          return PatientScaffold(
            currentRoute: RouteNames.patientMedications,
            detachedNav: true,
            title: 'Medication',
            body: EmptyStateView(
              icon: AppIcons.medication,
              title: 'Not found',
              message: 'This medication could not be loaded.',
            ),
          );
        }
        final history = MedicationsState.instance.dosesForMedication(med.id);

        return PatientScaffold(
          currentRoute: RouteNames.patientMedications,
          detachedNav: true,
          title: med.name,
          subtitle: '${med.dosage} · ${med.source.label}',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntry(
                index: 0,
                child: GlassCard(
                  frosted: true,
                  onTap: () => MedicationDetailSheet.show(context, med),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Dosage', value: med.dosage),
                      _InfoRow(label: 'Frequency', value: med.frequency),
                      _InfoRow(label: 'Form', value: med.form),
                      _InfoRow(label: 'Prescribed by', value: med.prescribedBy),
                      if (med.instructions != null)
                        _InfoRow(
                          label: 'Instructions',
                          value: med.instructions!,
                        ),
                      if (med.refillsLeft != null)
                        _InfoRow(
                          label: 'Refills left',
                          value: '${med.refillsLeft}',
                        ),
                      if (med.expiryDate != null)
                        _InfoRow(
                          label: 'Expires',
                          value: DateFormat.yMMMd().format(med.expiryDate!),
                        ),
                      _InfoRow(
                        label: 'Started',
                        value: DateFormat.yMMMd().format(med.startDate),
                      ),
                    ],
                  ),
                ),
              ),
              if (med.alert != null) ...[
                const SizedBox(height: AppSpacing.sm),
                StaggeredEntry(
                  index: 1,
                  child: _AlertBanner(alert: med.alert!),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              StaggeredEntry(
                index: 2,
                child: SectionLabel(
                  title: 'Dose history',
                  icon: AppIcons.time,
                  trailing: '${history.length} doses',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (history.isEmpty)
                StaggeredEntry(
                  index: 3,
                  child: GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.medication,
                      title: 'No dose history',
                      message: 'Logged doses will appear here.',
                      compact: true,
                    ),
                  ),
                )
              else
                StaggeredEntry(
                  index: 3,
                  child: GlassCard(
                    frosted: true,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      children: [
                        for (var i = 0; i < history.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              color: AppPalette.border(context),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () =>
                                    DoseDetailSheet.show(context, history[i]),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSm,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        history[i].status == DoseStatus.taken
                                            ? AppIcons.check
                                            : AppIcons.time,
                                        size: 14,
                                        color: history[i].status.color,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              DateFormat.yMMMd()
                                                  .add_jm()
                                                  .format(
                                                    history[i].scheduledAt,
                                                  ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                            ),
                                            Text(
                                              history[i].status.label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        history[i].status.color,
                                                    fontSize: 10,
                                                  ),
                                            ),
                                          ],
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
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.huge),
            ],
          ),
        );
      },
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.alert});
  final MedicationAlert alert;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Icon(AppIcons.alert, size: 16, color: alert.tint),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: alert.tint,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  alert.body,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

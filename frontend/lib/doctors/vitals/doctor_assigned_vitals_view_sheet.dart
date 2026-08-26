import 'package:flutter/material.dart';

import '../../shared/models/vital.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/glass_sheet.dart';
import 'doctor_assign_vitals_sheet.dart';

List<VitalKey> _sortedAssignedVitals(Set<VitalKey> assigned) {
  final list = assigned.toList()..sort((a, b) => a.label.compareTo(b.label));
  return list;
}

/// Read-only popup — what vitals this patient must track.
/// Full assign / threshold controls live under [DoctorAssignVitalsSheet].
class DoctorAssignedVitalsViewSheet {
  DoctorAssignedVitalsViewSheet._();

  static Future<void> show(
    BuildContext context, {
    required String patientId,
    required String patientName,
  }) {
    return GlassSheet.show<void>(
      context,
      title: 'Assigned vitals',
      subtitle: patientName,
      child: _AssignedVitalsViewBody(
        patientId: patientId,
        patientName: patientName,
      ),
    );
  }
}

/// Single-line tap target on the vitals panel — opens [DoctorAssignedVitalsViewSheet].
class DoctorAssignedVitalsPeek extends StatelessWidget {
  const DoctorAssignedVitalsPeek({
    super.key,
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final assigned = StaffState.instance.assignedVitalsForPatient(patientId);
    final summary = _summaryFor(assigned);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => DoctorAssignedVitalsViewSheet.show(
          context,
          patientId: patientId,
          patientName: patientName,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: GlassCard(
          frosted: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                AppIcons.lock,
                size: 16,
                color: assigned.isEmpty
                    ? AppPalette.textMuted(context)
                    : AppColors.doctorGreen,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assigned.isEmpty
                          ? 'Assigned vitals'
                          : 'Assigned vitals · ${assigned.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textMuted(context),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                AppIcons.chevronRight,
                size: 18,
                color: AppPalette.textMuted(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _summaryFor(Set<VitalKey> assigned) {
    final list = _sortedAssignedVitals(assigned);
    if (list.isEmpty) {
      return 'Tap to view or assign required vitals';
    }
    if (list.length <= 2) {
      return list.map((v) => v.label).join(' · ');
    }
    return '${list.take(2).map((v) => v.shortLabel).join(', ')} +${list.length - 2} more';
  }
}

class _AssignedVitalsViewBody extends StatelessWidget {
  const _AssignedVitalsViewBody({
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context) {
    final assigned = _sortedAssignedVitals(
      StaffState.instance.assignedVitalsForPatient(patientId),
    );
    final note = StaffState.instance.assignedVitalsNoteForPatient(patientId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Vitals this patient must log. Optional vitals they chose stay on their dashboard too.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (assigned.isEmpty)
            const EmptyStateView(
              icon: AppIcons.vitals,
              title: 'No vitals assigned',
              message:
                  'Assign the vitals this patient should track from their dashboard.',
              compact: true,
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: assigned.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final v = assigned[index];
                  return _AssignedVitalChip(vital: v);
                },
              ),
            ),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            GlassCard(
              frosted: true,
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.document,
                    size: 15,
                    color: AppPalette.textMuted(context),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      note,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Manage assignments',
            icon: AppIcons.settings,
            variant: AppButtonVariant.secondary,
            expand: true,
            onPressed: () {
              Navigator.of(context).pop();
              DoctorAssignVitalsSheet.show(
                context,
                patientId: patientId,
                patientName: patientName,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AssignedVitalChip extends StatelessWidget {
  const _AssignedVitalChip({required this.vital});

  final VitalKey vital;

  @override
  Widget build(BuildContext context) {
    final accent = vital.accent;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(vital.icon, color: accent, size: 17),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vital.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  vital.unit,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Icon(AppIcons.lock, size: 14, color: accent.withValues(alpha: 0.7)),
        ],
      ),
    );
  }
}

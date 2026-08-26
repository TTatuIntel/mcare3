import 'package:flutter/material.dart';

import '../../shared/models/vital.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/patient_sheet.dart';

/// Patient-facing sheet to choose which vitals are tracked.
/// Doctor-assigned vitals appear locked — only a clinician can de-assign.
class VitalPreferencesSheet {
  VitalPreferencesSheet._();

  static Future<void> show(BuildContext context) {
    return PatientSheet.show<void>(
      context,
      title: 'Your tracked vitals',
      subtitle:
          'Assigned vitals stay on your dashboard. Toggle optional ones anytime.',
      maxHeightFactor: 0.75,
      child: const _VitalPreferencesBody(),
    );
  }
}

class _VitalPreferencesBody extends StatefulWidget {
  const _VitalPreferencesBody();

  @override
  State<_VitalPreferencesBody> createState() => _VitalPreferencesBodyState();
}

class _VitalPreferencesBodyState extends State<_VitalPreferencesBody> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VitalsState.instance,
      builder: (context, _) {
        final state = VitalsState.instance;
        final selectable = state.selectableVitals;
        final assigned = selectable.where((v) => state.isAssigned(v)).toList();
        final optional = selectable.where((v) => !state.isAssigned(v)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (assigned.isNotEmpty) ...[
              _SectionHeader(
                icon: AppIcons.lock,
                label: 'Assigned by your care team',
                hint: 'Required',
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final v in assigned) ...[
                _VitalRow(
                  vital: v,
                  tracked: true,
                  locked: true,
                  onChanged: null,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            _SectionHeader(
              icon: AppIcons.add,
              label: 'Optional vitals',
              hint:
                  '${optional.where((v) => state.tracked.contains(v)).length}/${optional.length}',
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final v in optional) ...[
              _VitalRow(
                vital: v,
                tracked: state.tracked.contains(v),
                locked: false,
                onChanged: (next) async {
                  if (!next && state.isAssigned(v)) {
                    AppToast.show(
                      context,
                      message:
                          'Assigned vitals can only be changed by your care team.',
                      kind: AppToastKind.info,
                    );
                    return;
                  }
                  final ok = await state.toggleTracked(v, next);
                  if (!ok && !next) {
                    if (!context.mounted) return;
                    AppToast.show(
                      context,
                      message: 'This vital is required by your care team.',
                      kind: AppToastKind.info,
                    );
                  } else if (!ok) {
                    if (!context.mounted) return;
                    AppToast.show(
                      context,
                      message: 'Could not save your preference. Try again.',
                      kind: AppToastKind.error,
                    );
                  }
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.label, this.hint});

  final IconData icon;
  final String label;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: AppPalette.textMuted(context)),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppPalette.textMuted(context),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const Spacer(),
        if (hint != null)
          Text(
            hint!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppPalette.textFaint(context),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class _VitalRow extends StatelessWidget {
  const _VitalRow({
    required this.vital,
    required this.tracked,
    required this.locked,
    required this.onChanged,
  });

  final VitalKey vital;
  final bool tracked;
  final bool locked;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.accent;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tracked
            ? accent.withOpacity(0.06)
            : AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(
          color: tracked
              ? accent.withOpacity(0.28)
              : AppPalette.border(context),
        ),
      ),
      child: Row(
        children: [
          Container(
            height: 34,
            width: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.14),
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
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                Text(
                  locked ? 'Required by your care team' : vital.unit,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: locked ? accent : AppPalette.textMuted(context),
                    fontWeight: locked ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(
                AppIcons.lock,
                size: 16,
                color: accent.withOpacity(0.85),
              ),
            )
          else
            Transform.scale(
              scale: 0.85,
              child: Switch.adaptive(
                value: tracked,
                activeColor: accent,
                onChanged: onChanged,
              ),
            ),
        ],
      ),
    );
  }
}

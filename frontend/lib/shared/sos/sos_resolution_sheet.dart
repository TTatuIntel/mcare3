import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/glass_sheet.dart';

/// How an emergency ended, chosen rather than assumed.
///
/// Mirrors `SosEvent::RESOLUTIONS`; the server rejects anything else, so the
/// two lists must not drift.
enum SosResolution {
  patientSafe('patient_safe', 'Patient reached and safe', AppIcons.check),
  transported('transported', 'Transported to a facility', AppIcons.location),
  treatedOnSite('treated_on_site', 'Treated on site', AppIcons.records),
  careTeamHandling(
    'care_team_handling',
    'Handed to the care team',
    AppIcons.assignments,
  ),
  unreachable('unreachable', 'Could not reach the patient', AppIcons.alert),
  other('other', 'Something else', AppIcons.edit);

  const SosResolution(this.apiValue, this.label, this.icon);

  final String apiValue;
  final String label;
  final IconData icon;
}

/// What the responder chose.
class SosResolutionInput {
  const SosResolutionInput({required this.resolution, this.note});

  final SosResolution resolution;
  final String? note;
}

/// Asks how the emergency ended before closing it.
///
/// "Resolved" on its own told a reviewer nothing: a patient reached and safe,
/// a patient carried out by ambulance, and a patient nobody could reach were
/// all recorded identically. A named outcome makes the record answerable —
/// and because no list covers every emergency, "Something else" is a real
/// option that requires the responder to say what actually happened, rather
/// than forcing the nearest wrong choice.
class SosResolutionSheet {
  SosResolutionSheet._();

  static Future<SosResolutionInput?> show(
    BuildContext context, {
    required String patientName,
  }) {
    return GlassSheet.show<SosResolutionInput>(
      context,
      title: 'How did this end?',
      subtitle: 'Closing the emergency for $patientName',
      child: const _ResolutionBody(),
    );
  }
}

class _ResolutionBody extends StatefulWidget {
  const _ResolutionBody();

  @override
  State<_ResolutionBody> createState() => _ResolutionBodyState();
}

class _ResolutionBodyState extends State<_ResolutionBody> {
  SosResolution? _choice;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// "Something else" is only meaningful with the words that replace it.
  bool get _canSubmit {
    final choice = _choice;
    if (choice == null) return false;
    if (choice == SosResolution.other) return _note.text.trim().isNotEmpty;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in SosResolution.values)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _Option(
              option: option,
              selected: _choice == option,
              onTap: () => setState(() => _choice = option),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: _note,
          label: _choice == SosResolution.other
              ? 'What happened?'
              : 'Add detail (optional)',
          hint: _choice == SosResolution.other
              ? 'Describe how this emergency ended'
              : 'Anything the next reviewer should know',
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        if (_choice == SosResolution.other && _note.text.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Describe the outcome so the record means something later.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.warning,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: 'Close the emergency',
          icon: AppIcons.checkMark,
          expand: true,
          variant: AppButtonVariant.danger,
          onPressed: _canSubmit
              ? () => Navigator.of(context).pop(
                  SosResolutionInput(
                    resolution: _choice!,
                    note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SosResolution option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.10)
                : AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected ? accent : AppPalette.border(context),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                option.icon,
                size: 17,
                color: selected ? accent : AppPalette.textMuted(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  option.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? accent : AppPalette.ink(context),
                  ),
                ),
              ),
              if (selected) Icon(AppIcons.checkMark, size: 17, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

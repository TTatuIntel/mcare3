import 'package:flutter/material.dart';

import '../../core/env/app_env.dart';
import '../../shared/services/doctor_session_service.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

/// Clinical action recorded when a doctor resolves a vital alert.
enum AlertResolutionAction {
  patientContacted('patient_contacted', 'Patient contacted'),
  medicationAdjusted('medication_adjusted', 'Medication adjusted'),
  followUpScheduled('follow_up_scheduled', 'Follow-up scheduled'),
  monitored('monitored', 'Monitored / observed'),
  referred('referred', 'Referred to care'),
  readingError('reading_error', 'Reading error / false alarm'),
  other('other', 'Other action');

  const AlertResolutionAction(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AlertResolutionAction? fromApi(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final a in AlertResolutionAction.values) {
      if (a.apiValue == raw) return a;
    }
    return null;
  }

  String suggestedNote({String? patientName, String? vitalLabel}) {
    final who = patientName ?? 'the patient';
    final vital = vitalLabel ?? 'this reading';
    return switch (this) {
      AlertResolutionAction.patientContacted => 'Contacted $who about $vital.',
      AlertResolutionAction.medicationAdjusted =>
        'Reviewed medications with $who after $vital.',
      AlertResolutionAction.followUpScheduled =>
        'Scheduled follow-up for $who regarding $vital.',
      AlertResolutionAction.monitored =>
        'Monitoring $who; will recheck $vital.',
      AlertResolutionAction.referred =>
        'Referred $who for further care after $vital.',
      AlertResolutionAction.readingError =>
        'Confirmed $vital was a false alarm / device error.',
      AlertResolutionAction.other => '',
    };
  }
}

/// Human-readable label for a resolved alert (includes custom "other" text).
String formatAlertResolutionAction(StaffAlert alert) {
  if (alert.resolutionAction == AlertResolutionAction.other.apiValue) {
    final custom = alert.resolutionCustomAction?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return AlertResolutionAction.other.label;
  }
  return AlertResolutionAction.fromApi(alert.resolutionAction)?.label ??
      alert.resolutionAction ??
      'Resolved';
}

class AlertResolutionInput {
  const AlertResolutionInput({
    required this.action,
    required this.note,
    this.customAction,
  });

  final AlertResolutionAction action;
  final String note;
  final String? customAction;
}

/// Shared doctor flow — resolve an alert with required action + note.
class DoctorAlertResolveFlow {
  DoctorAlertResolveFlow._();

  static StaffAlert? _findAlert(String alertId) {
    for (final a in StaffState.instance.alerts) {
      if (a.id == alertId) return a;
    }
    return null;
  }

  static Future<bool> resolve(
    BuildContext context,
    StaffAlert alert, {
    String? successMessage,
  }) async {
    final ok = await DoctorAlertResolveSheet.showAndResolve(
      context,
      alert: alert,
    );
    if (!context.mounted) return ok;

    if (ok) {
      AppToast.success(
        context,
        successMessage ??
            '${alert.vital.label} alert resolved for ${alert.patientName}.',
      );
    }
    return ok;
  }

  static Future<bool> resolveById(
    BuildContext context,
    String alertId, {
    String? successMessage,
  }) async {
    final alert = _findAlert(alertId);
    if (alert == null) {
      AppToast.show(context, message: 'Alert not found.');
      return false;
    }
    return resolve(context, alert, successMessage: successMessage);
  }
}

/// Bottom sheet for documenting how a vital alert was resolved.
class DoctorAlertResolveSheet extends StatefulWidget {
  const DoctorAlertResolveSheet({super.key, required this.alert});

  final StaffAlert alert;

  static Future<AlertResolutionInput?> show(
    BuildContext context, {
    required StaffAlert alert,
  }) {
    return GlassSheet.show<AlertResolutionInput>(
      context,
      title: 'Resolve alert',
      subtitle: '${alert.patientName} · ${alert.vital.label}',
      child: DoctorAlertResolveSheet(alert: alert),
    );
  }

  static Future<bool> showAndResolve(
    BuildContext context, {
    required StaffAlert alert,
  }) {
    return GlassSheet.show<bool>(
      context,
      title: 'Resolve alert',
      subtitle: '${alert.patientName} · ${alert.vital.label}',
      child: _ResolveSubmitSheet(alert: alert),
    ).then((v) => v == true);
  }

  @override
  State<DoctorAlertResolveSheet> createState() =>
      _DoctorAlertResolveSheetState();
}

class _ResolveSubmitSheet extends StatefulWidget {
  const _ResolveSubmitSheet({required this.alert});
  final StaffAlert alert;

  @override
  State<_ResolveSubmitSheet> createState() => _ResolveSubmitSheetState();
}

class _ResolveSubmitSheetState extends State<_ResolveSubmitSheet> {
  bool _saving = false;

  Future<void> _submit(AlertResolutionInput input) async {
    setState(() => _saving = true);
    try {
      final ok = await StaffState.instance.resolveAlert(
        widget.alert.id,
        actionTaken: input.action.apiValue,
        note: input.note,
        customAction: input.customAction,
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _saving = false);
        AppToast.warn(context, 'Could not resolve alert. Try again.');
        return;
      }
      if (AppEnv.backendEnabled) {
        await DoctorSessionService.instance.syncFromApi();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not resolve alert. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ResolveFormBody(
      alert: widget.alert,
      saving: _saving,
      onSubmit: _saving ? null : _submit,
    );
  }
}

class _DoctorAlertResolveSheetState extends State<DoctorAlertResolveSheet> {
  @override
  Widget build(BuildContext context) {
    return _ResolveFormBody(
      alert: widget.alert,
      onSubmit: (input) => Navigator.of(context).pop(input),
    );
  }
}

class _ResolveFormBody extends StatefulWidget {
  const _ResolveFormBody({
    required this.alert,
    this.saving = false,
    required this.onSubmit,
  });

  final StaffAlert alert;
  final bool saving;
  final void Function(AlertResolutionInput input)? onSubmit;

  @override
  State<_ResolveFormBody> createState() => _ResolveFormBodyState();
}

class _ResolveFormBodyState extends State<_ResolveFormBody> {
  AlertResolutionAction? _action;
  final _noteCtrl = TextEditingController();
  final _customActionCtrl = TextEditingController();
  bool _noteEdited = false;
  String? _actionError;
  String? _customActionError;
  String? _noteError;

  @override
  void dispose() {
    _noteCtrl.dispose();
    _customActionCtrl.dispose();
    super.dispose();
  }

  void _selectAction(AlertResolutionAction action) {
    setState(() {
      _action = action;
      _actionError = null;
      if (!_noteEdited && action != AlertResolutionAction.other) {
        _noteCtrl.text = action.suggestedNote(
          patientName: widget.alert.patientName,
          vitalLabel: widget.alert.vital.label,
        );
        _noteError = null;
      }
      if (action != AlertResolutionAction.other) {
        _customActionError = null;
      }
    });
  }

  bool _validate() {
    final note = _noteCtrl.text.trim();
    final custom = _customActionCtrl.text.trim();
    String? actionError;
    String? customError;
    String? noteError;

    if (_action == null) {
      actionError = 'Select the action you took.';
    }
    if (_action == AlertResolutionAction.other && custom.length < 3) {
      customError = 'Describe the action (at least 3 characters).';
    }
    if (note.length < 4) {
      noteError = 'Add a brief clinical note (at least 4 characters).';
    }

    setState(() {
      _actionError = actionError;
      _customActionError = customError;
      _noteError = noteError;
    });
    return actionError == null && customError == null && noteError == null;
  }

  void _submit() {
    if (!_validate() || _action == null || widget.onSubmit == null) return;
    widget.onSubmit!(
      AlertResolutionInput(
        action: _action!,
        note: _noteCtrl.text.trim(),
        customAction: _action == AlertResolutionAction.other
            ? _customActionCtrl.text.trim()
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = AlertResolutionAction.values;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Action taken',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Pick one action — notes are suggested automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          if (_actionError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _actionError!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.critical,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < actions.length; i += 2) ...[
            if (i > 0) const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: _ActionChip(
                    label: actions[i].label,
                    selected: _action == actions[i],
                    onTap: () => _selectAction(actions[i]),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: i + 1 < actions.length
                      ? _ActionChip(
                          label: actions[i + 1].label,
                          selected: _action == actions[i + 1],
                          onTap: () => _selectAction(actions[i + 1]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
          if (_action == AlertResolutionAction.other) ...[
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Describe other action',
              hint: 'e.g. Escalated to on-call nurse',
              controller: _customActionCtrl,
              errorText: _customActionError,
              onChanged: (_) {
                if (_customActionError != null) {
                  setState(() => _customActionError = null);
                }
              },
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Clinical note',
            controller: _noteCtrl,
            maxLines: 3,
            hint: 'Brief note for the chart…',
            errorText: _noteError,
            onChanged: (_) {
              _noteEdited = true;
              if (_noteError != null) {
                setState(() => _noteError = null);
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Resolve alert',
            icon: AppIcons.check,
            expand: true,
            loading: widget.saving,
            onPressed: widget.onSubmit == null ? null : _submit,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent : accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected ? accent : accent.withOpacity(0.22),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected ? Colors.white : accent,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

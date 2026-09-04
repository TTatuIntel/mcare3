import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/env/app_env.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_layout.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/patient_sheet.dart';
import '../../shared/widgets/risk_badge.dart';

class SubmitVitalSheet {
  SubmitVitalSheet._();

  static Future<void> show(BuildContext context, {VitalKey? initial}) {
    return PatientSheet.show<void>(
      context,
      title: 'Log a vital',
      subtitle: 'Choose a tracked vital and enter your reading.',
      maxHeightFactor: 0.78,
      child: _Form(initial: initial),
    );
  }
}

List<VitalKey> _sortedTracked(Iterable<VitalKey> tracked) {
  return tracked.toList()..sort((a, b) => a.index.compareTo(b.index));
}

class _Form extends StatefulWidget {
  const _Form({this.initial});
  final VitalKey? initial;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late VitalKey _vital;
  final _primary = TextEditingController();
  final _secondary = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    VitalsState.instance.addListener(_onTrackedChanged);
    _vital = _resolveInitial(VitalsState.instance.tracked);
  }

  @override
  void dispose() {
    VitalsState.instance.removeListener(_onTrackedChanged);
    _primary.dispose();
    _secondary.dispose();
    _note.dispose();
    super.dispose();
  }

  VitalKey _resolveInitial(Set<VitalKey> tracked) {
    if (tracked.isEmpty) return VitalKey.heartRate;
    if (widget.initial != null && tracked.contains(widget.initial)) {
      return widget.initial!;
    }
    return _sortedTracked(tracked).first;
  }

  void _onTrackedChanged() {
    final tracked = VitalsState.instance.tracked;
    if (tracked.isEmpty) return;
    if (!tracked.contains(_vital)) {
      setState(() {
        _vital = _resolveInitial(tracked);
        _primary.clear();
        _secondary.clear();
      });
    }
  }

  double? get _v => double.tryParse(_primary.text);
  double? get _s => double.tryParse(_secondary.text);
  RiskLevel get _risk {
    final v = _v;
    if (v == null) return RiskLevel.unknown;
    return VitalRanges.defaults[_vital]!.assess(v);
  }

  Future<void> _save() async {
    final v = _v;
    if (v == null) {
      AppToast.warn(context, 'Enter a value.');
      return;
    }
    if (_vital.hasSecondaryValue && _s == null) {
      AppToast.warn(context, 'Enter both systolic and diastolic.');
      return;
    }
    setState(() => _saving = true);
    final draft = VitalReading(
      id: 'v_${DateTime.now().millisecondsSinceEpoch}',
      vital: _vital,
      value: v,
      secondaryValue: _s,
      recordedAt: DateTime.now(),
      risk: _risk,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    VitalReading saved;
    try {
      saved = await VitalsState.instance.recordReading(draft);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.warn(context, 'Could not save: $e');
      return;
    }
    // Optimistic local update for immediate feedback. When the backend is
    // enabled the server is authoritative (VitalAlertNotifier creates/resolves
    // the alert), and the next session sync replaces the list — so we only
    // create a local alert row in offline/mock mode to avoid divergence.
    if (_risk == RiskLevel.normal) {
      NotificationState.instance.resolveVitalAlerts(_vital);
    } else if (!AppEnv.backendEnabled &&
        (_risk == RiskLevel.warning || _risk == RiskLevel.critical)) {
      NotificationState.instance.upsertVitalAlert(
        vital: _vital,
        reading: saved,
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    AppToast.success(
      context,
      '${_vital.shortLabel} logged · ${saved.formatValue()} ${_vital.unit}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: VitalsState.instance,
      builder: (context, _) {
        final tracked = _sortedTracked(VitalsState.instance.tracked);
        if (tracked.isEmpty) {
          return EmptyStateView(
            icon: AppIcons.vitals,
            title: 'No vitals tracked',
            message:
                'Add vitals from your Vitals screen before logging a reading.',
            compact: true,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VitalSelector(
              tracked: tracked,
              value: _vital,
              onChanged: (v) => setState(() {
                _vital = v;
                _primary.clear();
                _secondary.clear();
              }),
            ),
            const SizedBox(height: AppLayout.fieldGap),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: _vital.accent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: _vital.accent.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(_vital.icon, color: _vital.accent, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _vital.label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _v == null
                              ? 'Enter a value below'
                              : _vital.hasSecondaryValue && _s != null
                              ? '${_v!.toStringAsFixed(0)}/${_s!.toStringAsFixed(0)} ${_vital.unit}'
                              : '${_v!.toStringAsFixed(_vital == VitalKey.temperature ? 1 : 0)} ${_vital.unit}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  RiskBadge(risk: _risk),
                ],
              ),
            ),
            const SizedBox(height: AppLayout.fieldGap),
            if (_vital.hasSecondaryValue)
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Systolic',
                      hint: '120',
                      controller: _primary,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\.]')),
                      ],
                      dense: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppTextField(
                      label: 'Diastolic',
                      hint: '80',
                      controller: _secondary,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\.]')),
                      ],
                      dense: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              )
            else
              AppTextField(
                label: 'Value (${_vital.unit})',
                hint: 'e.g. 72',
                controller: _primary,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\.]')),
                ],
                dense: true,
                onChanged: (_) => setState(() {}),
              ),
            const SizedBox(height: AppLayout.fieldGap),
            AppTextField(
              label: 'Note (optional)',
              hint: 'e.g. before breakfast',
              controller: _note,
              maxLines: 2,
              minLines: 2,
              dense: true,
            ),
            const SizedBox(height: AppLayout.sectionGap),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.ghost,
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: 'Save',
                    icon: AppIcons.check,
                    expand: true,
                    size: AppButtonSize.md,
                    loading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _VitalSelector extends StatelessWidget {
  const _VitalSelector({
    required this.tracked,
    required this.value,
    required this.onChanged,
  });

  final List<VitalKey> tracked;
  final VitalKey value;
  final ValueChanged<VitalKey> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your tracked vitals',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: AppPalette.ink(context),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tracked
              .map(
                (v) => _VitalChoice(
                  vital: v,
                  selected: v == value,
                  onTap: () => onChanged(v),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _VitalChoice extends StatelessWidget {
  const _VitalChoice({
    required this.vital,
    required this.selected,
    required this.onTap,
  });
  final VitalKey vital;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = vital.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c : c.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: selected ? c : c.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(vital.icon, color: selected ? Colors.white : c, size: 14),
            const SizedBox(width: 5),
            Text(
              vital.shortLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? Colors.white : c,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'doctor_vital_threshold_form.dart';
import '../models/vital.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_label.dart';

// ---------------------------------------------------------------------------
// Result returned when the form is submitted.
// ---------------------------------------------------------------------------

class VitalCatalogFormResult {
  const VitalCatalogFormResult({
    required this.label,
    required this.unit,
    required this.description,
    required this.thresholds,
    required this.alertConfig,
    this.delete = false,
  });

  final String label;
  final String unit;
  final String? description;
  final VitalThresholdFormResult thresholds;
  final VitalAlertConfig alertConfig;
  final bool delete;
}

// ---------------------------------------------------------------------------
// Main form widget
// ---------------------------------------------------------------------------

/// Full create / edit form for a vital catalog entry. Used from both the
/// admin catalog view and the doctor global vitals catalog.
///
/// Pass [entry] when editing an existing entry (null = create mode).
class VitalCatalogForm extends StatefulWidget {
  const VitalCatalogForm({super.key, this.entry});

  final VitalCatalogEntry? entry;

  @override
  State<VitalCatalogForm> createState() => _VitalCatalogFormState();
}

class _VitalCatalogFormState extends State<VitalCatalogForm> {
  late final TextEditingController _label;
  late final TextEditingController _unit;
  late final TextEditingController _description;
  late final GlobalKey<VitalThresholdFormState> _thresholdKey;

  // Alert config state
  late bool _enableWarning;
  late bool _enableCritical;
  late bool _autoResolve;
  late bool _escalationEnabled;
  late int _escalationMinutes;
  late final TextEditingController _critTitle;
  late final TextEditingController _warnTitle;

  String? _error;

  bool get _isBuiltin => widget.entry?.vital != null;
  bool get _isEdit => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final ac = e?.alertConfig ?? const VitalAlertConfig();

    _label = TextEditingController(text: e?.displayLabel ?? '');
    _unit = TextEditingController(text: e?.displayUnit ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _thresholdKey = GlobalKey<VitalThresholdFormState>();

    _enableWarning = ac.enableWarningAlerts;
    _enableCritical = ac.enableCriticalAlerts;
    _autoResolve = ac.autoResolveOnNormal;
    _escalationEnabled = ac.escalationEnabled;
    _escalationMinutes = ac.escalationDelayMinutes;
    _critTitle = TextEditingController(text: ac.criticalAlertTitle ?? '');
    _warnTitle = TextEditingController(text: ac.warningAlertTitle ?? '');
  }

  @override
  void dispose() {
    _label.dispose();
    _unit.dispose();
    _description.dispose();
    _critTitle.dispose();
    _warnTitle.dispose();
    super.dispose();
  }

  VitalAlertConfig _buildAlertConfig() => VitalAlertConfig(
        enableWarningAlerts: _enableWarning,
        enableCriticalAlerts: _enableCritical,
        autoResolveOnNormal: _autoResolve,
        escalationEnabled: _escalationEnabled,
        escalationDelayMinutes: _escalationMinutes,
        criticalAlertTitle:
            _critTitle.text.trim().isEmpty ? null : _critTitle.text.trim(),
        warningAlertTitle:
            _warnTitle.text.trim().isEmpty ? null : _warnTitle.text.trim(),
      );

  void _submit() {
    final label = _label.text.trim();
    final unit = _unit.text.trim();

    if (!_isBuiltin && label.isEmpty) {
      setState(() => _error = 'Vital name is required.');
      return;
    }
    if (!_isBuiltin && unit.isEmpty) {
      setState(() => _error = 'Measurement unit is required.');
      return;
    }

    final thresholds = _thresholdKey.currentState?.validateAndGetResult();
    if (thresholds == null) return;

    setState(() => _error = null);
    Navigator.of(context).pop(VitalCatalogFormResult(
      label: label,
      unit: unit,
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      thresholds: thresholds,
      alertConfig: _buildAlertConfig(),
    ));
  }

  void _delete() {
    Navigator.of(context).pop(const VitalCatalogFormResult(
      label: '',
      unit: '',
      description: null,
      thresholds: VitalThresholdFormResult(
        normalMin: 0,
        normalMax: 0,
        warningLow: 0,
        warningHigh: 0,
        criticalLow: 0,
        criticalHigh: 0,
        clear: true,
      ),
      alertConfig: VitalAlertConfig(),
      delete: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final initialRange = entry?.toRange() ??
        const VitalRiskRange(
          normalMin: 0,
          normalMax: 100,
          warningLow: 0,
          warningHigh: 110,
          criticalLow: 0,
          criticalHigh: 120,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Identity -------------------------------------------------------
          if (!_isBuiltin) ...[
            SectionLabel(
              title: 'Vital identity',
              icon: AppIcons.vitals,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: AppTextField(
                    label: 'Vital name',
                    controller: _label,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: AppTextField(
                    label: 'Unit (e.g. mg/dL)',
                    controller: _unit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(
              label: 'Clinical description (optional)',
              controller: _description,
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ---- Thresholds -----------------------------------------------------
          SectionLabel(
            title: 'Thresholds',
            icon: AppIcons.alert,
          ),
          const SizedBox(height: AppSpacing.sm),
          GlassCard(
            frosted: true,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: VitalThresholdForm(
              key: _thresholdKey,
              vital: entry?.vital,
              unit: entry?.displayUnit,
              useDecimals: entry?.vital == VitalKey.temperature ||
                  entry?.vital == VitalKey.weight,
              initial: initialRange,
              existingOverride: _isEdit,
              allowClear: false,
              embedded: true,
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // ---- Alert config ---------------------------------------------------
          SectionLabel(
            title: 'Alert & notification settings',
            icon: AppIcons.bell,
          ),
          const SizedBox(height: AppSpacing.sm),
          GlassCard(
            frosted: true,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                _SwitchRow(
                  label: 'Warning alerts',
                  subtitle: 'Notify when reading enters warning range',
                  value: _enableWarning,
                  onChanged: (v) => setState(() => _enableWarning = v),
                ),
                const Divider(height: 1),
                _SwitchRow(
                  label: 'Critical alerts',
                  subtitle: 'Notify when reading enters critical range',
                  value: _enableCritical,
                  accentColor: AppColors.critical,
                  onChanged: (v) => setState(() => _enableCritical = v),
                ),
                const Divider(height: 1),
                _SwitchRow(
                  label: 'Auto-resolve on normal',
                  subtitle: 'Clear active alert when reading returns to normal',
                  value: _autoResolve,
                  onChanged: (v) => setState(() => _autoResolve = v),
                ),
                const Divider(height: 1),
                _SwitchRow(
                  label: 'Escalation',
                  subtitle: 'Escalate unresolved alerts to next care tier',
                  value: _escalationEnabled,
                  onChanged: (v) => setState(() => _escalationEnabled = v),
                ),
                if (_escalationEnabled) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Escalate after (minutes)',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        SizedBox(
                          width: 80,
                          child: _NumField(
                            label: 'min',
                            initialValue: _escalationMinutes.toString(),
                            onChanged: (v) {
                              final parsed = int.tryParse(v);
                              if (parsed != null && parsed > 0) {
                                _escalationMinutes = parsed;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Custom alert titles
          const SizedBox(height: AppSpacing.sm),
          GlassCard(
            frosted: true,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Custom alert titles (optional)',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Critical alert title',
                  controller: _critTitle,
                  hint: '${entry?.displayLabel ?? 'Vital'} is critical',
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  label: 'Warning alert title',
                  controller: _warnTitle,
                  hint: '${entry?.displayLabel ?? 'Vital'} is outside range',
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.critical, fontSize: 12),
            ),
          ],

          const SizedBox(height: AppSpacing.lg),

          // ---- Actions --------------------------------------------------------
          Row(
            children: [
              if (_isEdit && !_isBuiltin)
                Expanded(
                  child: AppButton(
                    label: 'Delete vital',
                    variant: AppButtonVariant.ghost,
                    onPressed: _delete,
                  ),
                ),
              if (_isEdit && !_isBuiltin) const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: _isEdit ? 'Save changes' : 'Create vital',
                  onPressed: _submit,
                  expand: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.accentColor,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: value ? (accentColor ?? AppColors.success) : null,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accentColor ?? AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  const _NumField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: initialValue,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
      ),
      onChanged: onChanged,
    );
  }
}

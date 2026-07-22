import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/vital.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';

class VitalThresholdFormResult {
  const VitalThresholdFormResult({
    required this.normalMin,
    required this.normalMax,
    required this.warningLow,
    required this.warningHigh,
    required this.criticalLow,
    required this.criticalHigh,
    this.note,
    this.clear = false,
  });

  final double normalMin;
  final double normalMax;
  final double warningLow;
  final double warningHigh;
  final double criticalLow;
  final double criticalHigh;
  final String? note;
  final bool clear;
}

class VitalThresholdForm extends StatefulWidget {
  const VitalThresholdForm({
    super.key,
    this.vital,
    required this.initial,
    required this.existingOverride,
    this.allowClear = true,
    this.embedded = false,
    this.unit,
    this.useDecimals = false,
  });

  /// Null for staff-created custom vitals.
  final VitalKey? vital;
  final VitalRiskRange initial;
  final bool existingOverride;
  final bool allowClear;
  /// When true, hides padding and action buttons — parent handles submit.
  final bool embedded;
  /// Overrides the unit label shown in field hints. Falls back to vital.unit.
  final String? unit;
  /// When true, input fields are formatted / validated to one decimal place.
  final bool useDecimals;

  @override
  State<VitalThresholdForm> createState() => VitalThresholdFormState();
}

class VitalThresholdFormState extends State<VitalThresholdForm> {
  late final TextEditingController _normalMin;
  late final TextEditingController _normalMax;
  late final TextEditingController _warnLow;
  late final TextEditingController _warnHigh;
  late final TextEditingController _critLow;
  late final TextEditingController _critHigh;
  late final TextEditingController _note;
  String? _error;

  @override
  void initState() {
    super.initState();
    _normalMin = TextEditingController(text: _fmt(widget.initial.normalMin));
    _normalMax = TextEditingController(text: _fmt(widget.initial.normalMax));
    _warnLow = TextEditingController(text: _fmt(widget.initial.warningLow));
    _warnHigh = TextEditingController(text: _fmt(widget.initial.warningHigh));
    _critLow = TextEditingController(text: _fmt(widget.initial.criticalLow));
    _critHigh = TextEditingController(text: _fmt(widget.initial.criticalHigh));
    _note = TextEditingController();
  }

  bool get _useDecimals =>
      widget.useDecimals ||
      widget.vital == VitalKey.temperature ||
      widget.vital == VitalKey.weight;

  String _fmt(double v) =>
      _useDecimals ? v.toStringAsFixed(1) : v.toStringAsFixed(0);

  @override
  void didUpdateWidget(covariant VitalThresholdForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vital != widget.vital ||
        oldWidget.initial != widget.initial) {
      applyInitial(widget.initial);
    }
  }

  @override
  void dispose() {
    _normalMin.dispose();
    _normalMax.dispose();
    _warnLow.dispose();
    _warnHigh.dispose();
    _critLow.dispose();
    _critHigh.dispose();
    _note.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) => double.tryParse(c.text.trim());

  VitalThresholdFormResult? validateAndGetResult() {
    final nmin = _parse(_normalMin);
    final nmax = _parse(_normalMax);
    final wlow = _parse(_warnLow);
    final whigh = _parse(_warnHigh);
    final clow = _parse(_critLow);
    final chigh = _parse(_critHigh);
    if ([nmin, nmax, wlow, whigh, clow, chigh].any((v) => v == null)) {
      setState(() => _error = 'All fields are required and must be numbers.');
      return null;
    }
    if (!(clow! <= wlow! && wlow <= nmin! && nmin <= nmax! &&
        nmax <= whigh! && whigh <= chigh!)) {
      setState(() => _error =
          'Order must be: critical-low ≤ warning-low ≤ normal-min ≤ normal-max ≤ warning-high ≤ critical-high.');
      return null;
    }
    setState(() => _error = null);
    return VitalThresholdFormResult(
      normalMin: nmin,
      normalMax: nmax,
      warningLow: wlow,
      warningHigh: whigh,
      criticalLow: clow,
      criticalHigh: chigh,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
  }

  void _submit() {
    final result = validateAndGetResult();
    if (result == null) return;
    Navigator.of(context).pop(result);
  }

  void applyInitial(VitalRiskRange initial) {
    _normalMin.text = _fmt(initial.normalMin);
    _normalMax.text = _fmt(initial.normalMax);
    _warnLow.text = _fmt(initial.warningLow);
    _warnHigh.text = _fmt(initial.warningHigh);
    _critLow.text = _fmt(initial.criticalLow);
    _critHigh.text = _fmt(initial.criticalHigh);
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final unit = widget.unit ?? widget.vital?.unit ?? '';
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _NumField(
                label: 'Normal min ($unit)',
                controller: _normalMin,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _NumField(
                label: 'Normal max ($unit)',
                controller: _normalMax,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _NumField(
                label: 'Warning low',
                controller: _warnLow,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _NumField(
                label: 'Warning high',
                controller: _warnHigh,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _NumField(
                label: 'Critical low',
                controller: _critLow,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _NumField(
                label: 'Critical high',
                controller: _critHigh,
              ),
            ),
          ],
        ),
        if (!widget.embedded) ...[
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Clinical note (optional)',
            controller: _note,
            maxLines: 2,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: const TextStyle(
              color: AppColors.critical,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );

    if (widget.embedded) return fields;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          fields,
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (widget.allowClear && widget.existingOverride)
                Expanded(
                  child: AppButton(
                    label: 'Revert to default',
                    variant: AppButtonVariant.ghost,
                    onPressed: () => Navigator.of(context).pop(
                      const VitalThresholdFormResult(
                        normalMin: 0,
                        normalMax: 0,
                        warningLow: 0,
                        warningHigh: 0,
                        criticalLow: 0,
                        criticalHigh: 0,
                        clear: true,
                      ),
                    ),
                  ),
                ),
              if (widget.allowClear && widget.existingOverride)
                const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Save thresholds',
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

class _NumField extends StatelessWidget {
  const _NumField({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
      ],
    );
  }
}

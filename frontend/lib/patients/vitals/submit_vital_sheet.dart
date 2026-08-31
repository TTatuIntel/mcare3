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
      title: 'Log vitals',
      subtitle: 'Tap the vitals you measured, then enter your readings.',
      maxHeightFactor: 0.88,
      child: _Form(initial: initial),
    );
  }
}

List<VitalKey> _sortedTracked(Iterable<VitalKey> tracked) {
  return tracked.toList()..sort((a, b) => a.index.compareTo(b.index));
}

/// The text fields for one vital. Blood pressure is the only reading that
/// needs two numbers, so [secondary] stays unused for every other vital.
class _Entry {
  final TextEditingController primary = TextEditingController();
  final TextEditingController secondary = TextEditingController();

  /// A card the patient opened but never typed into is not an omission — they
  /// simply did not take that reading — so saving skips it rather than
  /// refusing the whole submission.
  bool get isBlank =>
      primary.text.trim().isEmpty && secondary.text.trim().isEmpty;

  void dispose() {
    primary.dispose();
    secondary.dispose();
  }
}

class _Form extends StatefulWidget {
  const _Form({this.initial});
  final VitalKey? initial;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  /// Presence in this map *is* selection. Rendered in VitalKey order so cards
  /// keep a stable position as the patient adds and removes them.
  final Map<VitalKey, _Entry> _entries = {};
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    VitalsState.instance.addListener(_onTrackedChanged);
    final first = _resolveInitial(VitalsState.instance.tracked);
    if (first != null) _entries[first] = _Entry();
  }

  @override
  void dispose() {
    VitalsState.instance.removeListener(_onTrackedChanged);
    for (final entry in _entries.values) {
      entry.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  VitalKey? _resolveInitial(Set<VitalKey> tracked) {
    if (tracked.isEmpty) return null;
    if (widget.initial != null && tracked.contains(widget.initial)) {
      return widget.initial;
    }
    return _sortedTracked(tracked).first;
  }

  /// A vital the patient stops tracking mid-edit must not stay on screen, but
  /// dropping one they already typed into would silently discard a reading —
  /// so only untouched cards are removed.
  void _onTrackedChanged() {
    final tracked = VitalsState.instance.tracked;
    final stale = _entries.keys
        .where((k) => !tracked.contains(k) && _entries[k]!.isBlank)
        .toList();
    if (stale.isEmpty) return;
    setState(() {
      for (final key in stale) {
        _entries.remove(key)!.dispose();
      }
    });
  }

  void _toggle(VitalKey vital) {
    final existing = _entries[vital];
    if (existing == null) {
      setState(() => _entries[vital] = _Entry());
      return;
    }
    // Closing a card the patient typed into would throw the reading away
    // without saying so. Keep it and ask them to clear the field instead.
    if (!existing.isBlank) {
      AppToast.warn(context, 'Clear the ${vital.shortLabel} value first.');
      return;
    }
    setState(() => _entries.remove(vital)!.dispose());
  }

  List<VitalKey> get _openVitals => _sortedTracked(_entries.keys);

  double? _primaryOf(VitalKey v) =>
      double.tryParse(_entries[v]!.primary.text.trim());

  double? _secondaryOf(VitalKey v) =>
      double.tryParse(_entries[v]!.secondary.text.trim());

  RiskLevel _riskOf(VitalKey v) {
    final value = _primaryOf(v);
    if (value == null) return RiskLevel.unknown;
    return VitalRanges.defaults[v]!.assess(value);
  }

  /// Vitals carrying a complete reading — exactly what Save would file now.
  List<VitalKey> get _filled => _openVitals.where((v) {
    if (_entries[v]!.isBlank) return false;
    if (_primaryOf(v) == null) return false;
    if (v.hasSecondaryValue && _secondaryOf(v) == null) return false;
    return true;
  }).toList();

  Future<void> _save() async {
    final drafts = <VitalReading>[];
    final now = DateTime.now();
    final note = _note.text.trim();

    for (final vital in _openVitals) {
      if (_entries[vital]!.isBlank) continue; // opened, not measured

      final value = _primaryOf(vital);
      if (value == null) {
        AppToast.warn(context, 'Enter a valid ${vital.shortLabel} value.');
        return;
      }
      final secondary = _secondaryOf(vital);
      if (vital.hasSecondaryValue && secondary == null) {
        AppToast.warn(context, 'Enter both systolic and diastolic.');
        return;
      }
      drafts.add(
        VitalReading(
          // Millisecond stamps collide when several drafts are built in the
          // same tick, so the vital name keeps each id distinct.
          id: 'v_${now.millisecondsSinceEpoch}_${vital.name}',
          vital: vital,
          value: value,
          secondaryValue: secondary,
          recordedAt: now,
          risk: _riskOf(vital),
          note: note.isEmpty ? null : note,
        ),
      );
    }

    if (drafts.isEmpty) {
      AppToast.warn(context, 'Enter at least one reading.');
      return;
    }

    setState(() => _saving = true);

    // There is no batch endpoint, so each reading is its own POST. A failure
    // partway through must not discard the readings that already saved, nor
    // the ones still unsent — both get re-entered by hand otherwise.
    final saved = <VitalReading>[];
    VitalKey? failedAt;
    Object? error;
    for (final draft in drafts) {
      try {
        saved.add(await VitalsState.instance.recordReading(draft));
      } catch (e) {
        failedAt = draft.vital;
        error = e;
        break;
      }
    }

    for (final reading in saved) {
      _applyAlertSideEffects(reading);
    }

    if (!mounted) return;

    if (failedAt != null) {
      setState(() {
        // Drop what is now persisted so a retry cannot double-post it, and
        // leave everything unsaved on screen exactly as it was typed.
        for (final reading in saved) {
          _entries.remove(reading.vital)?.dispose();
        }
        _saving = false;
      });
      AppToast.warn(
        context,
        saved.isEmpty
            ? 'Could not save: $error'
            : '${saved.length} saved · ${failedAt.shortLabel} failed: $error',
      );
      return;
    }

    Navigator.of(context).pop();
    AppToast.success(context, _successMessage(saved));
  }

  /// Mirrors the single-reading behaviour for each saved vital: the server is
  /// authoritative once the backend is on, so a local alert row is only
  /// invented in offline/mock mode to avoid diverging from it.
  void _applyAlertSideEffects(VitalReading reading) {
    if (reading.risk == RiskLevel.normal) {
      NotificationState.instance.resolveVitalAlerts(reading.vital);
    } else if (!AppEnv.backendEnabled &&
        (reading.risk == RiskLevel.warning ||
            reading.risk == RiskLevel.critical)) {
      NotificationState.instance.upsertVitalAlert(
        vital: reading.vital,
        reading: reading,
      );
    }
  }

  String _successMessage(List<VitalReading> saved) {
    if (saved.length == 1) {
      final r = saved.first;
      return '${r.vital.shortLabel} logged · ${r.formatValue()} ${r.vital.unit}';
    }
    return '${saved.length} vitals logged';
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

        final open = _openVitals;
        final readyCount = _filled.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VitalSelector(
              tracked: tracked,
              open: _entries.keys.toSet(),
              filled: _filled.toSet(),
              onToggle: _toggle,
            ),
            const SizedBox(height: AppLayout.fieldGap),
            if (open.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.ink(context).withOpacity(0.04),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Text(
                  'Tap a vital above to enter a reading.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final vital in open) ...[
                _VitalEntryCard(
                  vital: vital,
                  entry: _entries[vital]!,
                  risk: _riskOf(vital),
                  primary: _primaryOf(vital),
                  secondary: _secondaryOf(vital),
                  onChanged: () => setState(() {}),
                  onRemove: () => _toggle(vital),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.xs),
            AppTextField(
              label: 'Note (optional)',
              hint: open.length > 1
                  ? 'e.g. before breakfast — applies to all'
                  : 'e.g. before breakfast',
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
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    // Naming the count is what tells the patient that one tap
                    // is about to file several readings.
                    label: readyCount > 1 ? 'Save $readyCount vitals' : 'Save',
                    icon: AppIcons.check,
                    expand: true,
                    size: AppButtonSize.md,
                    loading: _saving,
                    onPressed: _saving || readyCount == 0 ? null : _save,
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

/// One reading's inputs, colour-coded to its vital so a stack of cards stays
/// scannable.
class _VitalEntryCard extends StatelessWidget {
  const _VitalEntryCard({
    required this.vital,
    required this.entry,
    required this.risk,
    required this.primary,
    required this.secondary,
    required this.onChanged,
    required this.onRemove,
  });

  final VitalKey vital;
  final _Entry entry;
  final RiskLevel risk;
  final double? primary;
  final double? secondary;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  String get _summary {
    if (primary == null) return 'Enter a value below';
    if (vital.hasSecondaryValue) {
      if (secondary == null) return 'Enter both numbers';
      return '${primary!.toStringAsFixed(0)}/'
          '${secondary!.toStringAsFixed(0)} ${vital.unit}';
    }
    final decimals = vital == VitalKey.temperature ? 1 : 0;
    return '${primary!.toStringAsFixed(decimals)} ${vital.unit}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vital.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: vital.accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(vital.icon, color: vital.accent, size: 22),
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
                      _summary,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              RiskBadge(risk: risk),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                tooltip: 'Remove ${vital.shortLabel}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (vital.hasSecondaryValue)
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Systolic',
                    hint: '120',
                    controller: entry.primary,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _NumberField(
                    label: 'Diastolic',
                    hint: '80',
                    controller: entry.secondary,
                    onChanged: onChanged,
                  ),
                ),
              ],
            )
          else
            _NumberField(
              label: 'Value (${vital.unit})',
              hint: 'e.g. 72',
              controller: entry.primary,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      hint: hint,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\.]'))],
      dense: true,
      onChanged: (_) => onChanged(),
    );
  }
}

class _VitalSelector extends StatelessWidget {
  const _VitalSelector({
    required this.tracked,
    required this.open,
    required this.filled,
    required this.onToggle,
  });

  final List<VitalKey> tracked;
  final Set<VitalKey> open;
  final Set<VitalKey> filled;
  final ValueChanged<VitalKey> onToggle;

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
        const SizedBox(height: 2),
        Text(
          'Tap any you measured — log one or several at once.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: tracked
              .map(
                (v) => _VitalChoice(
                  vital: v,
                  selected: open.contains(v),
                  hasValue: filled.contains(v),
                  onTap: () => onToggle(v),
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
    required this.hasValue,
    required this.onTap,
  });
  final VitalKey vital;
  final bool selected;

  /// A filled chip carries a reading Save will file. The tick is what
  /// distinguishes it from one that is merely open and still empty.
  final bool hasValue;
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
            Icon(
              hasValue ? Icons.check_circle_rounded : vital.icon,
              color: selected ? Colors.white : c,
              size: 14,
            ),
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

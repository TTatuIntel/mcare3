import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/env/app_env.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/vitals_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_motion.dart';
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
      subtitle: 'Pick how you want to log, then enter your readings.',
      maxHeightFactor: 0.88,
      child: _Form(initial: initial),
    );
  }
}

/// How the patient works through their readings.
///
/// Grouped stays the default — most people measure several vitals in one
/// sitting — but one-by-one exists for anyone who finds a stack of cards more
/// than they want on screen at once.
enum _LogMode {
  grouped,
  oneByOne;

  String get label => switch (this) {
    _LogMode.grouped => 'All at once',
    _LogMode.oneByOne => 'One by one',
  };

  IconData get icon => switch (this) {
    _LogMode.grouped => Icons.grid_view_rounded,
    _LogMode.oneByOne => Icons.format_list_numbered_rounded,
  };

  String get helper => switch (this) {
    _LogMode.grouped => 'Tap everything you measured and save it in one go.',
    _LogMode.oneByOne => 'Guided steps — one vital at a time, nothing missed.',
  };
}

/// The patient picks a way of working, not a setting they want to re-pick on
/// every reading, so the choice survives for the rest of the app session.
_LogMode _rememberedMode = _LogMode.grouped;

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

  void clear() {
    primary.clear();
    secondary.clear();
  }

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
  /// Presence in this map *is* selection in grouped mode, and the set of steps
  /// already visited in one-by-one mode. Rendered in VitalKey order so cards
  /// keep a stable position as the patient adds and removes them.
  final Map<VitalKey, _Entry> _entries = {};
  final _note = TextEditingController();
  _LogMode _mode = _rememberedMode;
  int _stepIndex = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    VitalsState.instance.addListener(_onTrackedChanged);
    final tracked = _sortedTracked(VitalsState.instance.tracked);
    final first = _resolveInitial(tracked);
    if (first != null) {
      _entries[first] = _Entry();
      _stepIndex = tracked.indexOf(first);
    }
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

  VitalKey? _resolveInitial(List<VitalKey> tracked) {
    if (tracked.isEmpty) return null;
    if (widget.initial != null && tracked.contains(widget.initial)) {
      return widget.initial;
    }
    return tracked.first;
  }

  /// A vital the patient stops tracking mid-edit must not stay on screen, but
  /// dropping one they already typed into would silently discard a reading —
  /// so only untouched cards are removed.
  void _onTrackedChanged() {
    if (!mounted) return;
    final tracked = VitalsState.instance.tracked;
    final stale = _entries.keys
        .where((k) => !tracked.contains(k) && _entries[k]!.isBlank)
        .toList();
    setState(() {
      for (final key in stale) {
        _entries.remove(key)!.dispose();
      }
      _ensureStepEntry();
    });
  }

  /// Keeps the walked-to step inside the tracked list and guarantees it has
  /// somewhere to type. Vitals can be dropped mid-edit, and a partial save
  /// removes the entries it managed to file — either can leave the step
  /// pointing at nothing. Call from inside a setState.
  void _ensureStepEntry() {
    if (_mode != _LogMode.oneByOne) return;
    final tracked = _sortedTracked(VitalsState.instance.tracked);
    if (tracked.isEmpty) return;
    _stepIndex = _stepIndex.clamp(0, tracked.length - 1);
    _entries.putIfAbsent(tracked[_stepIndex], _Entry.new);
  }

  void _setMode(_LogMode mode) {
    if (mode == _mode) return;
    final tracked = _sortedTracked(VitalsState.instance.tracked);
    setState(() {
      _mode = mode;
      _rememberedMode = mode;
      if (mode == _LogMode.oneByOne) {
        // Land on the card they were already working in so switching mid-entry
        // does not lose their place.
        final open = _openVitals;
        final anchor = open.isNotEmpty ? tracked.indexOf(open.first) : -1;
        if (anchor >= 0) _stepIndex = anchor;
        _ensureStepEntry();
      } else {
        // Steps walked past without measuring anything would otherwise
        // reappear here as a stack of empty cards.
        for (final key in _entries.keys.toList()) {
          if (_entries[key]!.isBlank) _entries.remove(key)!.dispose();
        }
        if (_entries.isEmpty && tracked.isNotEmpty) {
          _entries[tracked[_stepIndex.clamp(0, tracked.length - 1)]] = _Entry();
        }
      }
    });
  }

  void _goToStep(int index) {
    final tracked = _sortedTracked(VitalsState.instance.tracked);
    if (tracked.isEmpty) return;
    setState(() {
      _stepIndex = index.clamp(0, tracked.length - 1);
      _ensureStepEntry();
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

  void _clear(VitalKey vital) {
    final entry = _entries[vital];
    if (entry == null) return;
    setState(entry.clear);
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
        _ensureStepEntry();
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

  /// Naming the count is what tells the patient that one tap is about to file
  /// several readings.
  String _saveLabel(int ready) => ready > 1 ? 'Save $ready vitals' : 'Save';

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

        final filled = _filled.toSet();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeSwitcher(mode: _mode, onChanged: _saving ? null : _setMode),
            const SizedBox(height: AppLayout.fieldGap),
            if (_mode == _LogMode.grouped)
              ..._groupedBody(tracked, filled)
            else
              ..._steppedBody(tracked, filled),
            const SizedBox(height: AppSpacing.xs),
            AppTextField(
              label: 'Note (optional)',
              hint: filled.length > 1
                  ? 'e.g. before breakfast — applies to all'
                  : 'e.g. before breakfast',
              controller: _note,
              maxLines: 2,
              minLines: 2,
              dense: true,
            ),
            const SizedBox(height: AppLayout.sectionGap),
            ..._actions(context, tracked, filled.length),
          ],
        );
      },
    );
  }

  // --- Grouped: every measured vital on screen at once ----------------------

  List<Widget> _groupedBody(List<VitalKey> tracked, Set<VitalKey> filled) {
    final open = _openVitals;
    return [
      _VitalRail(
        vitals: tracked,
        stepped: false,
        solid: _entries.keys.toSet(),
        filled: filled,
        current: null,
        onTap: _toggle,
      ),
      const SizedBox(height: AppLayout.fieldGap),
      if (open.isEmpty)
        const _Hint(text: 'Tap a vital above to enter a reading.')
      else
        for (final vital in open) ...[
          _VitalEntryCard(
            vital: vital,
            entry: _entries[vital]!,
            risk: _riskOf(vital),
            primary: _primaryOf(vital),
            secondary: _secondaryOf(vital),
            onChanged: () => setState(() {}),
            onTrailing: () => _toggle(vital),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
    ];
  }

  // --- One by one: one card, walked through step by step --------------------

  List<Widget> _steppedBody(List<VitalKey> tracked, Set<VitalKey> filled) {
    final index = _stepIndex.clamp(0, tracked.length - 1);
    final vital = tracked[index];
    // Every path that moves the step already creates this; the fallback keeps a
    // card on screen rather than throwing if a rebuild ever outruns one.
    final entry = _entries.putIfAbsent(vital, _Entry.new);

    return [
      _StepHeader(vitals: tracked, index: index, filled: filled),
      const SizedBox(height: AppSpacing.md),
      _VitalRail(
        vitals: tracked,
        stepped: true,
        solid: filled,
        filled: filled,
        current: vital,
        onTap: (v) => _goToStep(tracked.indexOf(v)),
      ),
      const SizedBox(height: AppLayout.fieldGap),
      _VitalEntryCard(
        // A fresh subtree per step is what lets the first field take focus as
        // the patient walks forward.
        key: ValueKey(vital),
        vital: vital,
        entry: entry,
        risk: _riskOf(vital),
        primary: _primaryOf(vital),
        secondary: _secondaryOf(vital),
        focused: true,
        onChanged: () => setState(() {}),
        onTrailing: entry.isBlank ? null : () => _clear(vital),
      ),
      const SizedBox(height: AppSpacing.sm),
      if (entry.isBlank)
        const _Hint(text: 'Did not measure this one? Tap Next to skip it.'),
    ];
  }

  // --- Footer ---------------------------------------------------------------

  List<Widget> _actions(
    BuildContext context,
    List<VitalKey> tracked,
    int ready,
  ) {
    if (_mode == _LogMode.grouped) {
      return [
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.ghost,
                expand: true,
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: AppButton(
                label: _saveLabel(ready),
                icon: AppIcons.check,
                expand: true,
                size: AppButtonSize.md,
                loading: _saving,
                onPressed: _saving || ready == 0 ? null : _save,
              ),
            ),
          ],
        ),
      ];
    }

    final index = _stepIndex.clamp(0, tracked.length - 1);
    final isLast = index >= tracked.length - 1;
    return [
      // Finishing early must not mean tapping Next through every vital they
      // did not measure.
      if (ready > 0 && !isLast) ...[
        AppButton(
          label: ready == 1 ? 'Save 1 reading now' : 'Save $ready readings now',
          icon: AppIcons.check,
          variant: AppButtonVariant.ghost,
          expand: true,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      Row(
        children: [
          Expanded(
            child: AppButton(
              label: index == 0 ? 'Cancel' : 'Back',
              icon: index == 0 ? null : AppIcons.chevronLeft,
              variant: AppButtonVariant.ghost,
              expand: true,
              onPressed: _saving
                  ? null
                  : index == 0
                  ? () => Navigator.of(context).pop()
                  : () => _goToStep(index - 1),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: isLast
                ? AppButton(
                    label: _saveLabel(ready),
                    icon: AppIcons.check,
                    expand: true,
                    size: AppButtonSize.md,
                    loading: _saving,
                    onPressed: _saving || ready == 0 ? null : _save,
                  )
                : AppButton(
                    label: 'Next',
                    trailingIcon: AppIcons.chevronRight,
                    expand: true,
                    size: AppButtonSize.md,
                    onPressed: _saving ? null : () => _goToStep(index + 1),
                  ),
          ),
        ],
      ),
    ];
  }
}

/// The choice between logging everything together and being walked through one
/// vital at a time. Deliberately the loudest thing in the sheet: a patient who
/// never notices it is stuck with whichever flow suits them less.
class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.mode, required this.onChanged});

  final _LogMode mode;
  final ValueChanged<_LogMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'How would you like to log?',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AppPalette.ink(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Segmented(mode: mode, accent: accent, onChanged: onChanged),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                AppIcons.info,
                size: 14,
                color: AppPalette.textMuted(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  mode.helper,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.mode,
    required this.accent,
    required this.onChanged,
  });

  final _LogMode mode;
  final Color accent;
  final ValueChanged<_LogMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    const modes = _LogMode.values;
    final radius = BorderRadius.circular(AppSpacing.radiusPill);

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: radius,
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: AppMotion.micro,
            curve: AppMotion.easeOut,
            alignment: mode == modes.first
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 1 / modes.length,
              heightFactor: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final option in modes)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: option == mode,
                    label: '${option.label}. ${option.helper}',
                    child: InkWell(
                      onTap: onChanged == null
                          ? null
                          : () => onChanged!(option),
                      borderRadius: radius,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            option.icon,
                            size: 16,
                            color: option == mode
                                ? Colors.white
                                : AppPalette.textMuted(context),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: option == mode
                                        ? Colors.white
                                        : AppPalette.ink(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where the patient is in the guided flow, and how much of it is already
/// filled in — the reassurance that makes stepping feel finite.
class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.vitals,
    required this.index,
    required this.filled,
  });

  final List<VitalKey> vitals;
  final int index;
  final Set<VitalKey> filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Text(
                'STEP ${index + 1} OF ${vitals.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                vitals[index].label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppPalette.ink(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (filled.isNotEmpty)
              Text(
                '${filled.length} ready',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var i = 0; i < vitals.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.micro,
                  height: 5,
                  decoration: BoxDecoration(
                    color: filled.contains(vitals[i])
                        ? AppColors.success
                        : i == index
                        ? accent
                        : AppPalette.border(context),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One reading's inputs, colour-coded to its vital so a stack of cards stays
/// scannable. [focused] is the single-card treatment used by the guided flow:
/// bigger type, the reading echoed back, and the first field ready to type in.
class _VitalEntryCard extends StatelessWidget {
  const _VitalEntryCard({
    super.key,
    required this.vital,
    required this.entry,
    required this.risk,
    required this.primary,
    required this.secondary,
    required this.onChanged,
    required this.onTrailing,
    this.focused = false,
  });

  final VitalKey vital;
  final _Entry entry;
  final RiskLevel risk;
  final double? primary;
  final double? secondary;
  final VoidCallback onChanged;

  /// Removes the card in grouped mode, empties it in the guided flow — where
  /// there is nothing to remove, only a mistyped number to wipe.
  final VoidCallback? onTrailing;
  final bool focused;

  bool get _hasReading =>
      primary != null && (!vital.hasSecondaryValue || secondary != null);

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
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(focused ? AppSpacing.lg : AppSpacing.md),
      decoration: BoxDecoration(
        color: vital.accent.withValues(alpha: focused ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(
          focused ? AppSpacing.radiusLg : AppSpacing.radiusMd,
        ),
        border: Border.all(
          color: vital.accent.withValues(alpha: focused ? 0.32 : 0.2),
          width: focused ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (focused)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: vital.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  alignment: Alignment.center,
                  child: Icon(vital.icon, color: vital.accent, size: 22),
                )
              else
                Icon(vital.icon, color: vital.accent, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vital.label,
                      style:
                          (focused
                                  ? theme.textTheme.titleSmall
                                  : theme.textTheme.labelMedium)
                              ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      _summary,
                      style: focused && _hasReading
                          ? theme.textTheme.titleMedium?.copyWith(
                              color: vital.accent,
                              fontWeight: FontWeight.w800,
                            )
                          : theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              RiskBadge(risk: risk),
              if (onTrailing != null) ...[
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  onPressed: onTrailing,
                  icon: Icon(
                    focused ? Icons.backspace_outlined : Icons.close_rounded,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(4),
                  tooltip: focused
                      ? 'Clear ${vital.shortLabel}'
                      : 'Remove ${vital.shortLabel}',
                ),
              ],
            ],
          ),
          SizedBox(height: focused ? AppSpacing.md : AppSpacing.sm),
          if (vital.hasSecondaryValue)
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: 'Systolic',
                    hint: '120',
                    controller: entry.primary,
                    autofocus: focused,
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
              autofocus: focused,
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
    this.autofocus = false,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: label,
      hint: hint,
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\.]'))],
      dense: true,
      onChanged: (_) => onChanged(),
    );
  }
}

/// Doubles as the picker in grouped mode and the jump-to-step rail in the
/// guided flow — one row of chips, so the patient learns it once.
class _VitalRail extends StatelessWidget {
  const _VitalRail({
    required this.vitals,
    required this.stepped,
    required this.solid,
    required this.filled,
    required this.current,
    required this.onTap,
  });

  final List<VitalKey> vitals;
  final bool stepped;

  /// Chips drawn in the vital's full colour: the ones opened (grouped) or
  /// already carrying a reading (guided).
  final Set<VitalKey> solid;
  final Set<VitalKey> filled;
  final VitalKey? current;
  final ValueChanged<VitalKey> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stepped ? 'Jump to a vital' : 'Your tracked vitals',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppPalette.ink(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stepped
                        ? 'Tap any step to go straight to it.'
                        : 'Tap any you measured — log one or several at once.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!stepped && filled.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.successSoft(context),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '${filled.length} of ${vitals.length} ready',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: vitals
              .map(
                (v) => _VitalChoice(
                  vital: v,
                  selected: solid.contains(v),
                  hasValue: filled.contains(v),
                  ringed: v == current,
                  onTap: () => onTap(v),
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
    required this.ringed,
    required this.onTap,
  });
  final VitalKey vital;
  final bool selected;

  /// A filled chip carries a reading Save will file. The tick is what
  /// distinguishes it from one that is merely open and still empty.
  final bool hasValue;

  /// The step the guided flow is sitting on — outlined rather than filled so it
  /// never reads as "already done".
  final bool ringed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = vital.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: AnimatedContainer(
        duration: AppMotion.micro,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? c
              : ringed
              ? AppPalette.surface(context)
              : c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(
            color: selected || ringed ? c : c.withValues(alpha: 0.25),
            width: ringed && !selected ? 2 : 1,
          ),
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

/// Quiet one-liner used where the sheet needs to say what to do next.
class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppPalette.ink(context).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.info, size: 14, color: AppPalette.textMuted(context)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../shared/models/meal_plan.dart';
import '../../shared/state/meal_plans_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_sheet.dart';
import 'meal_widgets.dart';

/// Everything on one planned meal, plus the two things the patient can do
/// with it: say whether they followed it, and — when it is a meal they added
/// themselves — edit or remove it.
class MealDetailSheet {
  MealDetailSheet._();

  static Future<void> show(BuildContext context, StaffMealPlan meal) {
    return PatientSheet.show<void>(
      context,
      title: meal.title,
      subtitle:
          '${meal.mealType.label} · ${DateFormat.yMMMEd().format(meal.planDate)}',
      child: _MealDetailBody(planId: meal.id),
    );
  }
}

/// Reads the plan back out of the store on every build so the sheet reflects
/// a log recorded from inside it without the caller having to reopen it.
class _MealDetailBody extends StatelessWidget {
  const _MealDetailBody({required this.planId});

  final String planId;

  Future<void> _log(
    BuildContext context,
    StaffMealPlan meal,
    MealAdherence adherence,
  ) async {
    try {
      await MealPlansState.instance.logAdherence(meal, adherence);
      if (!context.mounted) return;
      AppToast.success(
        context,
        adherence.isLogged
            ? 'Marked as ${adherence.label.toLowerCase()}.'
            : 'Progress cleared.',
      );
    } catch (_) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not save that just now. Try again.');
    }
  }

  Future<void> _remove(BuildContext context, StaffMealPlan meal) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Remove this meal?',
      message:
          'It will be taken off your plan for '
          '${DateFormat.yMMMEd().format(meal.planDate)}.',
      confirmLabel: 'Remove',
      danger: true,
      icon: AppIcons.delete,
    );
    if (confirmed != true || !context.mounted) return;
    Navigator.of(context).pop();
    try {
      await MealPlansState.instance.removeSelfPlan(meal);
    } catch (_) {
      if (!context.mounted) return;
      AppToast.error(context, 'Could not remove that meal. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: MealPlansState.instance,
      builder: (context, _) {
        final meal = MealPlansState.instance.byId(planId);
        // Removed from under the sheet — nothing left to show.
        if (meal == null) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                MealMetaChip(
                  icon: meal.mealType.icon,
                  label: meal.mealType.label,
                  color: meal.mealType.color,
                ),
                if (meal.serveLabel != null)
                  MealMetaChip(icon: AppIcons.time, label: meal.serveLabel!),
                MealMetaChip(
                  icon: meal.source.icon,
                  label: meal.source.label,
                  color: meal.isSelfAdded
                      ? AppColors.info
                      : theme.colorScheme.primary,
                ),
                if ((meal.conditionTag ?? '').isNotEmpty)
                  MealMetaChip(
                    icon: AppIcons.vitals,
                    label: 'For ${meal.conditionTag}',
                    color: AppColors.warning,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            if ((meal.description ?? '').isNotEmpty) ...[
              Text(meal.description!, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.lg),
            ],

            if (meal.items.isNotEmpty) ...[
              Text(
                'What to eat',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppPalette.ink(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final item in meal.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: meal.mealType.color,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(item, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
            ],

            // Progress. Present for every plan, including a doctor's — the
            // record of what the patient actually ate is the point of it.
            Text(
              'Did you follow this meal?',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppPalette.ink(context),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (final option in const [
                  MealAdherence.followed,
                  MealAdherence.partial,
                  MealAdherence.skipped,
                ]) ...[
                  Expanded(
                    child: _AdherenceButton(
                      option: option,
                      selected: meal.adherence == option,
                      onTap: () => _log(
                        context,
                        meal,
                        meal.adherence == option
                            ? MealAdherence.pending
                            : option,
                      ),
                    ),
                  ),
                  if (option != MealAdherence.skipped)
                    const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            if (meal.macroSummary.isNotEmpty)
              PatientCompactInfoRow(
                label: 'Nutrition',
                value: meal.macroSummary,
              ),
            if ((meal.notes ?? '').isNotEmpty)
              PatientCompactInfoRow(
                label: meal.isSelfAdded ? 'Your note' : 'Care team note',
                value: meal.notes!,
              ),
            if (meal.assignedBy.isNotEmpty)
              PatientCompactInfoRow(
                label: meal.isSelfAdded ? 'Added by' : 'Assigned by',
                value: meal.assignedBy,
              ),
            PatientCompactInfoRow(
              label: 'Planned for',
              value: DateFormat.yMMMEd().format(meal.planDate),
            ),
            if (meal.loggedAt != null)
              PatientCompactInfoRow(
                label: 'Logged',
                value: DateFormat.yMMMEd().add_jm().format(meal.loggedAt!),
              ),

            if (meal.isSelfAdded) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Edit',
                      icon: AppIcons.edit,
                      variant: AppButtonVariant.secondary,
                      expand: true,
                      onPressed: () {
                        Navigator.of(context).pop();
                        MealEditorSheet.show(context, existing: meal);
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'Remove',
                      icon: AppIcons.delete,
                      variant: AppButtonVariant.danger,
                      expand: true,
                      onPressed: () => _remove(context, meal),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _AdherenceButton extends StatelessWidget {
  const _AdherenceButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final MealAdherence option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected
                ? option.color.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected
                  ? option.color.withValues(alpha: 0.55)
                  : AppPalette.border(context),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                option.icon,
                size: 18,
                color: selected ? option.color : AppPalette.textMuted(context),
              ),
              const SizedBox(height: 4),
              Text(
                option.shortLabel,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? option.color
                      : AppPalette.textMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add or edit a meal the patient plans for themselves. A clinician's plan is
/// never editable here — the sheet is only ever opened for self-added meals.
class MealEditorSheet {
  MealEditorSheet._();

  static Future<void> show(
    BuildContext context, {
    DateTime? date,
    StaffMealPlan? existing,
  }) {
    return PatientSheet.show<void>(
      context,
      title: existing == null ? 'Add a meal' : 'Edit meal',
      subtitle: existing == null
          ? 'Plan what you intend to eat, then log how it went.'
          : 'Only meals you added yourself can be changed.',
      maxHeightFactor: 0.9,
      child: _MealEditorForm(date: date, existing: existing),
    );
  }
}

class _MealEditorForm extends StatefulWidget {
  const _MealEditorForm({this.date, this.existing});

  final DateTime? date;
  final StaffMealPlan? existing;

  @override
  State<_MealEditorForm> createState() => _MealEditorFormState();
}

class _MealEditorFormState extends State<_MealEditorForm> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _calories;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late final TextEditingController _notes;
  final TextEditingController _item = TextEditingController();

  late MealType _mealType;
  late DateTime _date;
  TimeOfDay? _time;
  late List<String> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _calories = TextEditingController(
      text: existing?.calories?.toString() ?? '',
    );
    _protein = TextEditingController(text: existing?.protein ?? '');
    _carbs = TextEditingController(text: existing?.carbs ?? '');
    _fat = TextEditingController(text: existing?.fat ?? '');
    _notes = TextEditingController(text: existing?.notes ?? '');
    _items = List<String>.from(existing?.items ?? const <String>[]);
    _mealType = existing?.mealType ?? _defaultMealType();
    _date =
        existing?.planDate ??
        MealPlansState.dayOf(widget.date ?? DateTime.now());
    _time = _parseTime(existing?.serveTime);
  }

  /// Opening the sheet mid-afternoon should not default to breakfast.
  MealType _defaultMealType() {
    final hour = DateTime.now().hour;
    if (hour < 11) return MealType.breakfast;
    if (hour < 15) return MealType.lunch;
    if (hour < 21) return MealType.dinner;
    return MealType.snack;
  }

  static TimeOfDay? _parseTime(String? raw) {
    final parts = raw?.split(':');
    if (parts == null || parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String? get _serveTime {
    final time = _time;
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _notes.dispose();
    _item.dispose();
    super.dispose();
  }

  void _addItem() {
    final value = _item.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _items.add(value);
      _item.clear();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: kMealHistoryDays)),
      lastDate: DateTime(
        now.year,
        now.month,
        now.day,
      ).add(const Duration(days: kMealFutureDays)),
    );
    if (picked != null) setState(() => _date = MealPlansState.dayOf(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  String? _trimmed(TextEditingController c) {
    final value = c.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      AppToast.warn(context, 'Give the meal a name first.');
      return;
    }
    setState(() => _saving = true);

    final existing = widget.existing;
    final draft = StaffMealPlan(
      id: existing?.id ?? 'meal_local_${DateTime.now().microsecondsSinceEpoch}',
      patientId: existing?.patientId ?? '',
      patientName: existing?.patientName ?? '',
      title: _title.text.trim(),
      mealType: _mealType,
      description: _trimmed(_description),
      calories: int.tryParse(_calories.text.trim()),
      protein: _trimmed(_protein),
      carbs: _trimmed(_carbs),
      fat: _trimmed(_fat),
      notes: _trimmed(_notes),
      assignedAt: existing?.assignedAt ?? DateTime.now(),
      assignedBy: existing?.assignedBy ?? 'You',
      scheduledFor: _date,
      serveTime: _serveTime,
      conditionTag: existing?.conditionTag,
      items: List.unmodifiable(_items),
      source: MealPlanSource.patient,
      adherence: existing?.adherence ?? MealAdherence.pending,
      loggedAt: existing?.loggedAt,
      patientNote: existing?.patientNote,
    );

    try {
      if (existing == null) {
        await MealPlansState.instance.addSelfPlan(draft);
      } else {
        await MealPlansState.instance.updateSelfPlan(draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(
        context,
        existing == null ? 'Meal added to your plan.' : 'Meal updated.',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error(context, 'Could not save that meal. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _title,
          label: 'Meal',
          hint: 'e.g. Grilled fish with greens',
          autofocus: widget.existing == null,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AppSpacing.md),

        _FieldLabel('When'),
        Row(
          children: [
            Expanded(
              child: _PickerTile(
                icon: AppIcons.calendar,
                label: DateFormat.yMMMEd().format(_date),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PickerTile(
                icon: AppIcons.time,
                label: _time == null ? 'Any time' : _time!.format(context),
                onTap: _pickTime,
                onClear: _time == null
                    ? null
                    : () => setState(() => _time = null),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        _FieldLabel('Meal type'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: MealType.values.map((type) {
            final selected = type == _mealType;
            return ChoiceChip(
              label: Text(type.label),
              selected: selected,
              avatar: Icon(
                type.icon,
                size: 15,
                color: selected ? Colors.white : type.color,
              ),
              selectedColor: type.color,
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                color: selected ? Colors.white : null,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (_) => setState(() => _mealType = type),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),

        _FieldLabel('Foods (optional)'),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _item,
                hint: 'Add a food, then press +',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addItem(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton.icon(
              icon: AppIcons.add,
              semanticLabel: 'Add food to this meal',
              onPressed: _addItem,
            ),
          ],
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (var i = 0; i < _items.length; i++)
                InputChip(
                  label: Text(_items[i]),
                  onDeleted: () => setState(() => _items.removeAt(i)),
                  deleteIcon: const Icon(AppIcons.close, size: 15),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          controller: _description,
          label: 'Notes on portion or preparation (optional)',
          maxLines: 3,
          minLines: 2,
        ),
        const SizedBox(height: AppSpacing.md),

        _FieldLabel('Nutrition (optional)'),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _calories,
                label: 'kcal',
                hint: '450',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppTextField(
                controller: _protein,
                label: 'Protein',
                hint: '30 g',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppTextField(
                controller: _carbs,
                label: 'Carbs',
                hint: '45 g',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppTextField(controller: _fat, label: 'Fat', hint: '10 g'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          controller: _notes,
          label: 'Anything to tell your care team (optional)',
          maxLines: 2,
          minLines: 1,
        ),
        const SizedBox(height: AppSpacing.xl),

        AppButton(
          label: widget.existing == null ? 'Add to my plan' : 'Save changes',
          icon: AppIcons.meals,
          expand: true,
          loading: _saving,
          onPressed: _saving ? null : _submit,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: AppPalette.ink(context),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: Icon(
                    AppIcons.close,
                    size: 15,
                    color: AppPalette.textMuted(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

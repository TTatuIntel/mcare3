import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../shared/models/meal_plan.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/glass_sheet.dart';

void showDoctorAssignMealSheet(
  BuildContext context, {
  required String patientId,
  required String patientName,
}) {
  GlassSheet.show(
    context,
    title: 'Assign meal plan',
    subtitle: patientName,
    child: _AssignMealForm(patientId: patientId, patientName: patientName),
  );
}

class _AssignMealForm extends StatefulWidget {
  const _AssignMealForm({required this.patientId, required this.patientName});

  final String patientId;
  final String patientName;

  @override
  State<_AssignMealForm> createState() => _AssignMealFormState();
}

class _AssignMealFormState extends State<_AssignMealForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _condition = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _notes = TextEditingController();
  final _item = TextEditingController();

  MealType _mealType = MealType.general;
  final List<String> _items = [];

  /// The days this plan is assigned for. Starts as today; a doctor building a
  /// week's timetable adds the rest, and one call writes all of them.
  late final List<DateTime> _days = [_today];
  TimeOfDay? _time;

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _condition.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _notes.dispose();
    _item.dispose();
    super.dispose();
  }

  String? get _serveTime {
    final time = _time;
    if (time == null) return null;
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }

  void _addItem() {
    final value = _item.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _items.add(value);
      _item.clear();
    });
  }

  Future<void> _addDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _days.isEmpty ? _today : _days.last,
      firstDate: _today.subtract(const Duration(days: 7)),
      lastDate: _today.add(const Duration(days: 90)),
    );
    if (picked == null) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    if (_days.contains(day)) return;
    setState(() {
      _days
        ..add(day)
        ..sort();
    });
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

  Future<void> _submit(BuildContext ctx) async {
    if (_title.text.trim().isEmpty) {
      AppToast.warn(ctx, 'Meal title is required.');
      return;
    }
    if (_days.isEmpty) {
      AppToast.warn(ctx, 'Pick at least one day to assign this to.');
      return;
    }

    final plan = StaffMealPlan(
      id: 'meal_${DateTime.now().millisecondsSinceEpoch}',
      patientId: widget.patientId,
      patientName: widget.patientName,
      title: _title.text.trim(),
      mealType: _mealType,
      description: _trimmed(_description),
      calories: int.tryParse(_calories.text.trim()),
      protein: _trimmed(_protein),
      carbs: _trimmed(_carbs),
      fat: _trimmed(_fat),
      notes: _trimmed(_notes),
      assignedAt: DateTime.now(),
      assignedBy: StaffState.currentDoctorDisplayName() ?? 'Doctor',
      scheduledFor: _days.first,
      serveTime: _serveTime,
      conditionTag: _trimmed(_condition),
      items: List.unmodifiable(_items),
    );

    final dayCount = _days.length;
    // Optimistic: pop immediately, API fires in background.
    if (ctx.mounted) Navigator.of(ctx).pop();
    final ok = await StaffState.instance.addMealPlan(plan, days: _days);
    if (!mounted) return;
    if (ok) {
      AppToast.success(
        context,
        dayCount == 1
            ? 'Meal plan assigned to ${widget.patientName}.'
            : '$dayCount days assigned to ${widget.patientName}.',
      );
    } else {
      AppToast.error(context, 'Failed to save meal plan. Please try again.');
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
          label: 'Meal title',
          hint: 'e.g. Low-sodium breakfast',
          autofocus: true,
        ),
        const SizedBox(height: AppSpacing.md),
        _Label('Meal type'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: MealType.values.map((t) {
            final selected = t == _mealType;
            return ChoiceChip(
              label: Text(t.label),
              selected: selected,
              avatar: Icon(
                t.icon,
                size: 15,
                color: selected ? Colors.white : t.color,
              ),
              selectedColor: t.color,
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                color: selected ? Colors.white : null,
                fontWeight: FontWeight.w600,
              ),
              onSelected: (_) => setState(() => _mealType = t),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),

        // Scheduling. Assigning the same meal across several days is the
        // normal case for a nutrition timetable, so days are a list.
        _Label('Assign to days'),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _days.length; i++)
              InputChip(
                label: Text(DateFormat.MMMd().format(_days[i])),
                avatar: const Icon(AppIcons.calendar, size: 14),
                onDeleted: _days.length == 1
                    ? null
                    : () => setState(() => _days.removeAt(i)),
                deleteIcon: const Icon(AppIcons.close, size: 15),
              ),
            ActionChip(
              label: const Text('Add day'),
              avatar: const Icon(AppIcons.add, size: 15),
              onPressed: _addDay,
            ),
            ActionChip(
              label: Text(_time == null ? 'Any time' : _time!.format(context)),
              avatar: const Icon(AppIcons.time, size: 15),
              onPressed: _pickTime,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        AppTextField(
          controller: _condition,
          label: 'Prescribed for (optional)',
          hint: 'e.g. Type 2 diabetes, Hypertension',
          helperText: 'Shown to the patient so the advice has a reason.',
        ),
        const SizedBox(height: AppSpacing.md),

        _Label('Foods (optional)'),
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
          label: 'Description',
          hint: 'What to eat, foods to avoid, preparation tips…',
          maxLines: 3,
          minLines: 2,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _calories,
                label: 'Calories (kcal)',
                hint: '450',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _Label('Macros (optional)'),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _protein,
                label: 'Protein',
                hint: '30g',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppTextField(
                controller: _carbs,
                label: 'Carbs',
                hint: '45g',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppTextField(controller: _fat, label: 'Fat', hint: '10g'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _notes,
          label: 'Clinical notes (optional)',
          hint: 'Additional guidance for the patient…',
          maxLines: 2,
          minLines: 1,
        ),
        const SizedBox(height: AppSpacing.xl),
        Builder(
          builder: (ctx) => AppButton(
            label: _days.length == 1
                ? 'Assign meal plan'
                : 'Assign to ${_days.length} days',
            icon: AppIcons.meals,
            expand: true,
            onPressed: () => _submit(ctx),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppPalette.ink(context),
        ),
      ),
    );
  }
}

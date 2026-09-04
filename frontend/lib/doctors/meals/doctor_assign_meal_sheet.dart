import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  const _AssignMealForm({
    required this.patientId,
    required this.patientName,
  });

  final String patientId;
  final String patientName;

  @override
  State<_AssignMealForm> createState() => _AssignMealFormState();
}

class _AssignMealFormState extends State<_AssignMealForm> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _calories = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  final _notes = TextEditingController();
  MealType _mealType = MealType.general;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext ctx) async {
    if (_title.text.trim().isEmpty) {
      AppToast.warn(ctx, 'Meal title is required.');
      return;
    }
    final calories = int.tryParse(_calories.text.trim());
    final plan = StaffMealPlan(
      id: 'meal_${DateTime.now().millisecondsSinceEpoch}',
      patientId: widget.patientId,
      patientName: widget.patientName,
      title: _title.text.trim(),
      mealType: _mealType,
      description:
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      calories: calories,
      protein: _protein.text.trim().isEmpty ? null : _protein.text.trim(),
      carbs: _carbs.text.trim().isEmpty ? null : _carbs.text.trim(),
      fat: _fat.text.trim().isEmpty ? null : _fat.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      assignedAt: DateTime.now(),
      assignedBy: StaffState.currentDoctorDisplayName() ?? 'Doctor',
    );
    // Optimistic: pop immediately, API fires in background.
    if (ctx.mounted) Navigator.of(ctx).pop();
    final ok = await StaffState.instance.addMealPlan(plan);
    if (!mounted) return;
    if (ok) {
      AppToast.success(context, 'Meal plan assigned to ${widget.patientName}.');
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
        Text(
          'Meal type',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppPalette.ink(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
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
        Text(
          'Macros (optional)',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppPalette.ink(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
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
              child: AppTextField(
                controller: _fat,
                label: 'Fat',
                hint: '10g',
              ),
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
            label: 'Assign meal plan',
            icon: AppIcons.meals,
            expand: true,
            onPressed: () => _submit(ctx),
          ),
        ),
      ],
    );
  }
}

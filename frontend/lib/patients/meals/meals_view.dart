import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/constants/route_names.dart';
import '../../shared/models/meal_plan.dart';
import '../../shared/state/meal_plans_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/app_page_route.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/glass_floating_button.dart';
import '../../shared/widgets/patient_page_blocks.dart';
import '../../shared/widgets/patient_scaffold.dart';
import '../../shared/widgets/section_label.dart';
import 'meal_plan_sheets.dart';
import 'meal_widgets.dart';

/// The patient's nutrition page: a day-by-day timetable of the meals their
/// care team assigned and the ones they planned themselves, with the progress
/// log that tells the care team whether the plan is actually being followed.
class MealsView extends StatefulWidget {
  const MealsView({super.key});

  @override
  State<MealsView> createState() => _MealsViewState();
}

class _MealsViewState extends State<MealsView> {
  late DateTime _selected = MealPlansState.dayOf(DateTime.now());

  bool get _isToday => _selected == MealPlansState.dayOf(DateTime.now());

  String get _dayLabel {
    final today = MealPlansState.dayOf(DateTime.now());
    final diff = _selected.difference(today).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => DateFormat('EEE, MMM d').format(_selected),
    };
  }

  Future<void> _log(StaffMealPlan meal, MealAdherence adherence) async {
    try {
      await MealPlansState.instance.logAdherence(meal, adherence);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not save that just now. Try again.');
    }
  }

  /// One tap to close out a day that went to plan. Only offered when the day
  /// still has unlogged meals and is not in the future.
  Future<void> _followAll(List<StaffMealPlan> plans) async {
    final pending = plans.where((p) => !p.adherence.isLogged).toList();
    for (final plan in pending) {
      await _log(plan, MealAdherence.followed);
    }
    if (!mounted) return;
    AppToast.success(
      context,
      '${pending.length} meal${pending.length == 1 ? '' : 's'} marked followed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PatientScaffold(
      currentRoute: RouteNames.patientMeals,
      title: 'Meals',
      subtitle: 'Your nutrition plan, day by day',
      maxContentWidth: 900,
      floatingActionButton: GlassFloatingButton(
        icon: AppIcons.add,
        label: 'Add meal',
        accent: AppColors.success,
        dynamicColors: const [AppColors.success, AppColors.brandIndigo],
        onPressed: () => MealEditorSheet.show(context, date: _selected),
      ),
      body: AnimatedBuilder(
        animation: MealPlansState.instance,
        builder: (context, _) {
          final plans = MealPlansState.instance.plansForDate(_selected);
          final pending = plans.where((p) => !p.adherence.isLogged).length;
          final isFuture = _selected.isAfter(
            MealPlansState.dayOf(DateTime.now()),
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const StaggeredEntry(index: 0, child: PatientDateHeader()),
              const SizedBox(height: AppSpacing.md),

              StaggeredEntry(
                index: 1,
                child: MealDayStrip(
                  selected: _selected,
                  onSelected: (day) => setState(() => _selected = day),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              StaggeredEntry(
                index: 2,
                child: MealProgressBar(dayPlans: plans, dayLabel: _dayLabel),
              ),
              const SizedBox(height: AppSpacing.lg),

              StaggeredEntry(
                index: 3,
                child: SectionLabel(
                  title: '$_dayLabel’s plan',
                  icon: AppIcons.meals,
                  trailing: plans.isEmpty ? null : '${plans.length}',
                  actionLabel: pending > 0 && !isFuture ? 'Follow all' : null,
                  onAction: pending > 0 && !isFuture
                      ? () => _followAll(plans)
                      : null,
                ),
              ),

              if (plans.isEmpty)
                StaggeredEntry(
                  index: 4,
                  child: EmptyStateView(
                    icon: AppIcons.meals,
                    title: _isToday
                        ? 'Nothing planned for today'
                        : 'Nothing planned for this day',
                    message:
                        'Plans your care team assigns show up here. You can '
                        'also add meals you intend to eat and track them.',
                    actionLabel: 'Add a meal',
                    onAction: () =>
                        MealEditorSheet.show(context, date: _selected),
                    compact: true,
                  ),
                )
              else
                ..._buildTimetable(context, plans),

              const SizedBox(height: AppSpacing.huge),
            ],
          );
        },
      ),
    );
  }

  /// Meals grouped under their slot, in the order they are eaten.
  List<Widget> _buildTimetable(
    BuildContext context,
    List<StaffMealPlan> plans,
  ) {
    final widgets = <Widget>[];
    var entry = 4;
    MealType? lastType;

    for (var i = 0; i < plans.length; i++) {
      final plan = plans[i];
      if (plan.mealType != lastType) {
        widgets.add(
          StaggeredEntry(
            index: entry++,
            child: _SlotHeader(type: plan.mealType),
          ),
        );
        lastType = plan.mealType;
      }
      widgets.add(
        StaggeredEntry(
          index: entry++,
          child: _MealRow(
            meal: plan,
            onLog: (adherence) => _log(plan, adherence),
          ),
        ),
      );
      final isLastOfSlot =
          i == plans.length - 1 || plans[i + 1].mealType != plan.mealType;
      if (!isLastOfSlot) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Divider(height: 1, color: AppPalette.border(context)),
          ),
        );
      }
    }
    return widgets;
  }
}

class _SlotHeader extends StatelessWidget {
  const _SlotHeader({required this.type});

  final MealType type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.md,
        bottom: AppSpacing.xs,
        left: 2,
      ),
      child: Row(
        children: [
          Text(
            type.label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: type.color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(height: 1, color: AppPalette.border(context)),
          ),
        ],
      ),
    );
  }
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal, required this.onLog});

  final StaffMealPlan meal;
  final ValueChanged<MealAdherence> onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final followed = meal.adherence == MealAdherence.followed;
    final subtitle = [
      if (meal.serveLabel != null) meal.serveLabel!,
      if (meal.isSelfAdded) 'Added by you' else meal.assignedBy,
      if (meal.macroSummary.isNotEmpty) meal.macroSummary,
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => MealDetailSheet.show(context, meal),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: meal.mealType.color.withValues(
                    alpha: followed ? 0.18 : 0.10,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  followed ? AppIcons.check : meal.mealType.icon,
                  color: followed ? AppColors.success : meal.mealType.color,
                  size: 19,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: meal.adherence == MealAdherence.skipped
                            ? TextDecoration.lineThrough
                            : null,
                        color: meal.adherence == MealAdherence.skipped
                            ? AppPalette.textMuted(context)
                            : null,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    if ((meal.conditionTag ?? '').isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      MealMetaChip(
                        icon: AppIcons.vitals,
                        label: 'For ${meal.conditionTag}',
                        color: AppColors.warning,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              MealAdherenceChip(adherence: meal.adherence, onChanged: onLog),
            ],
          ),
        ),
      ),
    );
  }
}

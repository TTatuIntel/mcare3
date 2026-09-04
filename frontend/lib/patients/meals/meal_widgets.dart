import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/models/meal_plan.dart';
import '../../shared/state/meal_plans_state.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_icons.dart';
import '../../shared/widgets/patient_page_blocks.dart';

/// How far either side of today the timetable strip runs. Three weeks of
/// history matches the default window used by the vitals insights, so the two
/// progress surfaces agree on what "recent" means.
const int kMealHistoryDays = 21;
const int kMealFutureDays = 14;

/// Horizontal day picker. A dot under a day means meals are planned for it —
/// green once every one of them is logged, so a glance shows where the gaps
/// are. Today keeps a ring even when another day is selected.
class MealDayStrip extends StatefulWidget {
  const MealDayStrip({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  State<MealDayStrip> createState() => _MealDayStripState();
}

class _MealDayStripState extends State<MealDayStrip> {
  static const double _chipWidth = 52;
  static const double _gap = AppSpacing.sm;

  final ScrollController _controller = ScrollController();

  List<DateTime> get _days {
    final today = MealPlansState.dayOf(DateTime.now());
    final start = today.subtract(const Duration(days: kMealHistoryDays));
    return List.generate(
      kMealHistoryDays + kMealFutureDays + 1,
      (i) => start.add(Duration(days: i)),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnSelected());
  }

  @override
  void didUpdateWidget(covariant MealDayStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _centerOnSelected();
  }

  /// Brings the chosen day into view. Called on first layout so the strip
  /// never opens scrolled three weeks into the past.
  void _centerOnSelected() {
    if (!mounted || !_controller.hasClients) return;
    final selected = MealPlansState.dayOf(widget.selected);
    final index = _days.indexWhere((d) => d == selected);
    if (index < 0) return;
    final viewport = _controller.position.viewportDimension;
    final target =
        (index * (_chipWidth + _gap)) - (viewport / 2) + (_chipWidth / 2);
    _controller.animateTo(
      target.clamp(0.0, _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = MealPlansState.dayOf(DateTime.now());
    final selected = MealPlansState.dayOf(widget.selected);
    final days = _days;

    return SizedBox(
      height: 66,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, index) {
          final day = days[index];
          final plans = MealPlansState.instance.plansForDate(day);
          return _DayChip(
            width: _chipWidth,
            day: day,
            isToday: day == today,
            isSelected: day == selected,
            planCount: plans.length,
            allLogged:
                plans.isNotEmpty && plans.every((p) => p.adherence.isLogged),
            onTap: () => widget.onSelected(day),
          );
        },
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.width,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.planCount,
    required this.allLogged,
    required this.onTap,
  });

  final double width;
  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final int planCount;
  final bool allLogged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final ink = isSelected ? Colors.white : AppPalette.ink(context);
    final muted = isSelected ? Colors.white70 : AppPalette.textMuted(context);
    final plannedLabel = planCount == 0
        ? 'no meals planned'
        : '$planCount meal${planCount == 1 ? '' : 's'} planned';

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${DateFormat.yMMMEd().format(day)}, $plannedLabel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: width,
            decoration: BoxDecoration(
              color: isSelected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                color: isSelected
                    ? accent
                    : isToday
                    ? accent.withValues(alpha: 0.55)
                    : AppPalette.border(context),
                width: isToday && !isSelected ? 1.4 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.E().format(day).substring(0, 1),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${day.day}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                _PlanDots(
                  planCount: planCount,
                  allLogged: allLogged,
                  onAccent: isSelected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanDots extends StatelessWidget {
  const _PlanDots({
    required this.planCount,
    required this.allLogged,
    required this.onAccent,
  });

  final int planCount;
  final bool allLogged;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    if (planCount == 0) return const SizedBox(height: 4);
    final color = onAccent
        ? Colors.white
        : allLogged
        ? AppColors.success
        : Theme.of(context).colorScheme.primary;
    final dots = planCount > 3 ? 3 : planCount;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < dots; i++)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
      ],
    );
  }
}

/// Progress across the plan: how much of the selected day is logged, the
/// three-week adherence rate and the current streak. Sits on the page
/// background — ruled top and bottom rather than boxed into a card.
class MealProgressBar extends StatelessWidget {
  const MealProgressBar({
    super.key,
    required this.dayPlans,
    required this.dayLabel,
  });

  final List<StaffMealPlan> dayPlans;
  final String dayLabel;

  @override
  Widget build(BuildContext context) {
    final state = MealPlansState.instance;
    final logged = dayPlans.where((p) => p.adherence.isLogged).length;
    final followed = dayPlans
        .where((p) => p.adherence == MealAdherence.followed)
        .length;
    final rate = state.adherenceRate(days: kMealHistoryDays);
    final streak = state.followedStreak;
    final progress = dayPlans.isEmpty ? 0.0 : logged / dayPlans.length;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: AppPalette.border(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PatientHeroStat(
                label: dayLabel,
                value: dayPlans.isEmpty
                    ? 'No meals'
                    : '$followed of ${dayPlans.length} followed',
                accent: dayPlans.isNotEmpty && followed == dayPlans.length
                    ? AppColors.success
                    : null,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Last $kMealHistoryDays days',
                value: rate == null ? '—' : '${(rate * 100).round()}%',
                accent: rate == null
                    ? null
                    : rate >= 0.8
                    ? AppColors.success
                    : rate >= 0.5
                    ? AppColors.warning
                    : AppColors.critical,
              ),
              const PatientHeroStatDivider(),
              PatientHeroStat(
                label: 'Streak',
                value: streak == 0
                    ? '—'
                    : '$streak day${streak == 1 ? '' : 's'}',
                accent: streak > 0 ? AppColors.success : null,
              ),
            ],
          ),
          if (dayPlans.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor: AppPalette.surfaceMuted(context),
                valueColor: AlwaysStoppedAnimation(
                  progress == 1
                      ? AppColors.success
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The progress control on a meal row. Opens a menu rather than cycling
/// blindly, so "skipped" is never one mis-tap away from "followed".
class MealAdherenceChip extends StatelessWidget {
  const MealAdherenceChip({
    super.key,
    required this.adherence,
    required this.onChanged,
    this.enabled = true,
  });

  final MealAdherence adherence;
  final ValueChanged<MealAdherence> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logged = adherence.isLogged;
    final color = logged ? adherence.color : AppPalette.textMuted(context);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: logged
            ? color.withValues(alpha: 0.12)
            : AppPalette.surfaceMuted(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(
          color: logged
              ? color.withValues(alpha: 0.35)
              : AppPalette.border(context),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(adherence.icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            adherence.shortLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );

    if (!enabled) return Opacity(opacity: 0.6, child: chip);

    return PopupMenuButton<MealAdherence>(
      tooltip: 'Record whether you followed this meal',
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in MealAdherence.values)
          PopupMenuItem(
            value: option,
            height: 42,
            child: Row(
              children: [
                Icon(
                  option.icon,
                  size: 17,
                  color: option.isLogged
                      ? option.color
                      : AppPalette.textMuted(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  option == MealAdherence.pending ? 'Clear' : option.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: option == adherence
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
                if (option == adherence) ...[
                  const Spacer(),
                  Icon(AppIcons.checkMark, size: 15, color: option.color),
                ],
              ],
            ),
          ),
      ],
      child: chip,
    );
  }
}

/// Small tinted label — meal source, condition, serve time.
class MealMetaChip extends StatelessWidget {
  const MealMetaChip({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? AppPalette.textMuted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tint,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

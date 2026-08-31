import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/patient_chart_api.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';
import 'app_icons.dart';
import 'glass_sheet.dart';

/// The one time filter, for every staff screen that reads over a window.
///
/// It used to be a labelled row of preset chips wrapped over two lines, in
/// each screen that needed one. That cost a header's worth of height on a
/// phone to say something the control could say in a single line, and it only
/// ever offered round numbers of days — a review of last month, or of the
/// fortnight an incident sits in, had to be counted out by hand.
///
/// One line: what window is showing, the dates it means, and a step either
/// side of it. Everything else — presets, calendar spans, a range picked off
/// a month grid — lives behind the tap, where it can be given room.
class PeriodFilterBar extends StatelessWidget {
  const PeriodFilterBar({
    super.key,
    required this.period,
    required this.onChanged,
    this.busy = false,
    this.accent,
    this.title = 'Period',
    this.subtitle = 'Every section answers from the window you choose.',
    this.dense = false,
  });

  final ChartPeriod period;
  final ValueChanged<ChartPeriod> onChanged;

  /// A reload is in flight — the control stays readable but refuses input,
  /// so a fast double tap cannot leave the window and the data disagreeing.
  final bool busy;
  final Color? accent;
  final String title;
  final String subtitle;

  /// Drops the range text when the caller is already printing the dates.
  final bool dense;

  /// Whether the window already runs up to today — there is no "next" past it.
  bool get _atPresent {
    final window = period.resolve();
    final now = DateTime.now();
    return !window.to.isBefore(DateTime(now.year, now.month, now.day));
  }

  /// Steps the window by its own length, so a reader comparing month against
  /// month never has to open the picker twice to do it.
  void _step(int direction) {
    final window = period.resolve();
    final span = period.spanDays().clamp(1, ChartPeriod.maxDays);
    final shift = Duration(days: span * direction);
    var from = window.from.add(shift);
    var to = window.to.add(shift);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    if (to.isAfter(today)) {
      final overshoot = to.difference(today);
      from = from.subtract(overshoot);
      to = today;
    }
    onChanged(ChartPeriod.range(from, to));
  }

  Future<void> _open(BuildContext context) async {
    final picked = await PeriodPickerSheet.show(
      context,
      current: period,
      title: title,
      subtitle: subtitle,
      accent: accent,
    );
    if (picked != null && picked != period) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = accent ?? theme.colorScheme.primary;
    final enabled = !busy;

    final steppers = busy
        ? const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: SizedBox(
              height: 13,
              width: 13,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StepButton(
                icon: AppIcons.chevronLeft,
                tooltip: 'Previous ${period.spanDays()} days',
                onTap: () => _step(-1),
              ),
              _StepButton(
                icon: AppIcons.chevronRight,
                tooltip: 'Next ${period.spanDays()} days',
                onTap: _atPresent ? null : () => _step(1),
              ),
            ],
          );

    final rangeText = Text(
      period.rangeText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: AppPalette.textMuted(context),
        fontSize: 10.5,
      ),
    );

    final pill = _PeriodPill(
      label: period.label,
      accent: tint,
      onTap: enabled ? () => _open(context) : null,
    );

    // A filter that cannot say which window it is showing is not a filter.
    // Squeezed onto one line, the label collapsed to "L…" and the dates to
    // "Jul 30 – Aug …" — the two facts the control exists to state. On a
    // narrow screen the range moves to its own line instead of competing
    // with the pill and the steppers for the same few pixels.
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 380;

        if (!tight || dense) {
          return Row(
            children: [
              pill,
              if (!dense) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: rangeText),
              ],
              const Spacer(),
              steppers,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: pill),
                const Spacer(),
                steppers,
              ],
            ),
            const SizedBox(height: 2),
            rangeText,
          ],
        );
      },
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(color: accent.withValues(alpha: 0.42)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.calendar, size: 12, color: accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(AppIcons.expandMore, size: 15, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null
        ? AppPalette.border(context)
        : AppPalette.textMuted(context);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon, size: 19, color: color),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ picker

/// Presets and a calendar, in the one place a period is chosen.
class PeriodPickerSheet {
  PeriodPickerSheet._();

  static Future<ChartPeriod?> show(
    BuildContext context, {
    required ChartPeriod current,
    String title = 'Period',
    String subtitle = 'Every section answers from the window you choose.',
    Color? accent,
  }) => GlassSheet.show<ChartPeriod>(
    context,
    title: title,
    subtitle: subtitle,
    leadingIcon: AppIcons.calendar,
    leadingColor: accent,
    maxWidth: 460,
    child: _PeriodPickerBody(current: current, accent: accent),
  );
}

class _PeriodPickerBody extends StatefulWidget {
  const _PeriodPickerBody({required this.current, this.accent});

  final ChartPeriod current;
  final Color? accent;

  @override
  State<_PeriodPickerBody> createState() => _PeriodPickerBodyState();
}

class _PeriodPickerBodyState extends State<_PeriodPickerBody> {
  late ChartPeriod _selected = widget.current;
  late DateTime _start;
  late DateTime _end;

  /// The calendar always shows the window that is selected, however it was
  /// chosen — picking "Last month" and then nudging one day is a normal way
  /// to arrive at the window someone actually wants.
  @override
  void initState() {
    super.initState();
    final window = widget.current.resolve();
    _start = DateUtils.dateOnly(window.from);
    _end = DateUtils.dateOnly(window.to);
  }

  void _choose(ChartPeriod period) {
    final window = period.resolve();
    setState(() {
      _selected = period;
      _start = DateUtils.dateOnly(window.from);
      _end = DateUtils.dateOnly(window.to);
    });
  }

  void _chooseRange(DateTime start, DateTime end) {
    setState(() {
      _start = start;
      _end = end;
      _selected = ChartPeriod.range(start, end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accent ?? theme.colorScheme.primary;
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final span = _selected.spanDays();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PickerGroup(
          label: 'Quick',
          children: [
            for (final preset in ChartPeriod.calendarPresets(now))
              _PresetChip(
                label: preset.label,
                accent: accent,
                selected: _selected.key == preset.key,
                onTap: () => _choose(preset),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _PickerGroup(
          label: 'Rolling window',
          children: [
            for (final preset in ChartPeriod.presets)
              _PresetChip(
                label: preset.label,
                accent: accent,
                selected: _selected.key == preset.key,
                onTap: () => _choose(preset),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _PickerGroup(
          label: 'Pick the days',
          trailing: _selected.isCustom ? 'Custom range' : null,
          children: const [],
        ),
        const SizedBox(height: AppSpacing.xs),
        PeriodRangeCalendar(
          firstDate: DateTime(today.year - 3, today.month, today.day),
          lastDate: today,
          start: _start,
          end: _end,
          accent: accent,
          maxSpanDays: ChartPeriod.maxDays,
          onChanged: _chooseRange,
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Icon(AppIcons.calendar, size: 14, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${_selected.label} · ${_selected.rangeText}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.ink(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '$span ${span == 1 ? 'day' : 'days'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'Apply period',
                icon: AppIcons.checkMark,
                expand: true,
                onPressed: () => Navigator.of(context).pop(_selected),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PickerGroup extends StatelessWidget {
  const _PickerGroup({
    required this.label,
    required this.children,
    this.trailing,
  });

  final String label;
  final List<Widget> children;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w900,
                fontSize: 9.5,
                letterSpacing: 0.8,
              ),
            ),
            if (trailing != null) ...[
              const Spacer(),
              Text(
                trailing!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                ),
              ),
            ],
          ],
        ),
        if (children.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: children,
          ),
        ],
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : AppPalette.surfaceAlt(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.55)
                  : AppPalette.border(context),
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? accent : AppPalette.textMuted(context),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- calendar

/// A month grid that selects a range in two taps.
///
/// Flutter's own range picker takes the whole screen and its own route, which
/// is a lot of ceremony for "the fortnight around the incident". This stays
/// inside the sheet the presets are in, so a reader can start from a preset
/// and adjust an edge without losing sight of what they picked.
class PeriodRangeCalendar extends StatefulWidget {
  const PeriodRangeCalendar({
    super.key,
    required this.firstDate,
    required this.lastDate,
    required this.start,
    required this.end,
    required this.onChanged,
    this.accent,
    this.maxSpanDays,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime start;
  final DateTime end;

  /// Both dates, always — the grid never reports a half-made range.
  final void Function(DateTime start, DateTime end) onChanged;
  final Color? accent;

  /// Longest range the reader is allowed to build, because the server will
  /// not read a longer one. Days past it are shown disabled rather than
  /// silently trimmed after the fact.
  final int? maxSpanDays;

  @override
  State<PeriodRangeCalendar> createState() => _PeriodRangeCalendarState();
}

class _PeriodRangeCalendarState extends State<PeriodRangeCalendar> {
  late DateTime _month = DateTime(widget.end.year, widget.end.month);

  /// The first tap of a new range. While it is set the grid is waiting for
  /// the second tap, and shows the range it would make under the pointer.
  DateTime? _anchor;
  bool _monthMode = false;

  @override
  void didUpdateWidget(PeriodRangeCalendar old) {
    super.didUpdateWidget(old);
    // A preset was chosen above — follow it, and drop a half-made range.
    if (old.end != widget.end || old.start != widget.start) {
      _anchor = null;
      _month = DateTime(widget.end.year, widget.end.month);
    }
  }

  DateTime get _minMonth =>
      DateTime(widget.firstDate.year, widget.firstDate.month);

  DateTime get _maxMonth =>
      DateTime(widget.lastDate.year, widget.lastDate.month);

  bool get _canGoBack => _month.isAfter(_minMonth);

  bool get _canGoForward => _month.isBefore(_maxMonth);

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  /// The latest day still selectable given where the range was anchored.
  DateTime get _selectableLast {
    final anchor = _anchor;
    final max = widget.maxSpanDays;
    if (anchor == null || max == null) return widget.lastDate;
    final cap = anchor.add(Duration(days: max - 1));
    return cap.isBefore(widget.lastDate) ? cap : widget.lastDate;
  }

  /// And the earliest, for a range built backwards from its end.
  DateTime get _selectableFirst {
    final anchor = _anchor;
    final max = widget.maxSpanDays;
    if (anchor == null || max == null) return widget.firstDate;
    final cap = anchor.subtract(Duration(days: max - 1));
    return cap.isAfter(widget.firstDate) ? cap : widget.firstDate;
  }

  bool _selectable(DateTime day) =>
      !day.isBefore(_selectableFirst) && !day.isAfter(_selectableLast);

  void _tap(DateTime day) {
    final anchor = _anchor;
    if (anchor == null) {
      setState(() => _anchor = day);
      return;
    }
    setState(() => _anchor = null);
    widget.onChanged(
      day.isBefore(anchor) ? day : anchor,
      day.isBefore(anchor) ? anchor : day,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = widget.accent ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _StepButton(
                icon: AppIcons.chevronLeft,
                tooltip: 'Previous month',
                onTap: _canGoBack && !_monthMode ? () => _shiftMonth(-1) : null,
              ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    onTap: () => setState(() => _monthMode = !_monthMode),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat.yMMMM().format(_month),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppPalette.ink(context),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            _monthMode
                                ? AppIcons.expandLess
                                : AppIcons.expandMore,
                            size: 16,
                            color: AppPalette.textMuted(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _StepButton(
                icon: AppIcons.chevronRight,
                tooltip: 'Next month',
                onTap: _canGoForward && !_monthMode
                    ? () => _shiftMonth(1)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_monthMode)
            _MonthYearGrid(
              month: _month,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              accent: accent,
              onPicked: (picked) => setState(() {
                _month = picked;
                _monthMode = false;
              }),
            )
          else
            _DayGrid(
              month: _month,
              start: widget.start,
              end: widget.end,
              anchor: _anchor,
              accent: accent,
              selectable: _selectable,
              onTap: _tap,
            ),
          if (_anchor != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Now pick the day the period ends.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.month,
    required this.start,
    required this.end,
    required this.anchor,
    required this.accent,
    required this.selectable,
    required this.onTap,
  });

  final DateTime month;
  final DateTime start;
  final DateTime end;
  final DateTime? anchor;
  final Color accent;
  final bool Function(DateTime day) selectable;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final firstWeekday = localizations.firstDayOfWeekIndex;

    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    // DateTime.weekday is 1 (Monday) to 7 (Sunday); the localisations index
    // Sunday at 0, so normalise before working out the leading blanks.
    final firstOfMonth = DateTime(month.year, month.month).weekday % 7;
    final leading = (firstOfMonth - firstWeekday + 7) % 7;
    final cells = ((leading + daysInMonth) / 7).ceil() * 7;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    localizations.narrowWeekdays[(firstWeekday + i) % 7],
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w800,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var row = 0; row < cells ~/ 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _dayCell(context, row * 7 + col - leading + 1)),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(BuildContext context, int dayOfMonth) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    if (dayOfMonth < 1 || dayOfMonth > daysInMonth) {
      return const SizedBox(height: 34);
    }

    final day = DateTime(month.year, month.month, dayOfMonth);
    final today = DateUtils.dateOnly(DateTime.now());
    final enabled = selectable(day);

    // While a range is being built the grid previews from the anchor, so the
    // reader can see what the second tap would give them.
    final from = anchor ?? start;
    final to = anchor ?? end;
    final isEdge =
        DateUtils.isSameDay(day, from) || DateUtils.isSameDay(day, to);
    final inRange = anchor == null && !day.isBefore(start) && !day.isAfter(end);

    final theme = Theme.of(context);
    final Color background;
    final Color foreground;
    if (isEdge) {
      background = accent;
      foreground = Colors.white;
    } else if (inRange) {
      background = accent.withValues(alpha: 0.13);
      foreground = AppPalette.ink(context);
    } else {
      background = Colors.transparent;
      foreground = enabled
          ? AppPalette.ink(context)
          : AppPalette.border(context);
    }

    // Square the inner edges so a run of days reads as one continuous band.
    final joinsLeft = inRange && !DateUtils.isSameDay(day, start);
    final joinsRight = inRange && !DateUtils.isSameDay(day, end);
    final radius = BorderRadius.horizontal(
      left: Radius.circular(joinsLeft ? 0 : AppSpacing.radiusSm),
      right: Radius.circular(joinsRight ? 0 : AppSpacing.radiusSm),
    );

    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: background,
          borderRadius: isEdge
              ? BorderRadius.circular(AppSpacing.radiusSm)
              : radius,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            onTap: enabled ? () => onTap(day) : null,
            child: Container(
              alignment: Alignment.center,
              decoration: DateUtils.isSameDay(day, today) && !isEdge
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(color: accent.withValues(alpha: 0.55)),
                    )
                  : null,
              child: Text(
                '$dayOfMonth',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: isEdge ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Jump a year at a time rather than tapping the month arrow twelve times.
class _MonthYearGrid extends StatefulWidget {
  const _MonthYearGrid({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.accent,
    required this.onPicked,
  });

  final DateTime month;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color accent;
  final ValueChanged<DateTime> onPicked;

  @override
  State<_MonthYearGrid> createState() => _MonthYearGridState();
}

class _MonthYearGridState extends State<_MonthYearGrid> {
  late int _year = widget.month.year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canBack = _year > widget.firstDate.year;
    final canForward = _year < widget.lastDate.year;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(
              icon: AppIcons.chevronLeft,
              tooltip: 'Previous year',
              onTap: canBack ? () => setState(() => _year--) : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '$_year',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: AppPalette.ink(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _StepButton(
              icon: AppIcons.chevronRight,
              tooltip: 'Next year',
              onTap: canForward ? () => setState(() => _year++) : null,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var row = 0; row < 4; row++)
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(child: _monthCell(context, row * 3 + col + 1)),
            ],
          ),
      ],
    );
  }

  Widget _monthCell(BuildContext context, int monthNumber) {
    final value = DateTime(_year, monthNumber);
    final enabled =
        !value.isBefore(
          DateTime(widget.firstDate.year, widget.firstDate.month),
        ) &&
        !value.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month));
    final selected = DateUtils.isSameMonth(value, widget.month);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected
            ? widget.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: enabled ? () => widget.onPicked(value) : null,
          child: Container(
            height: 32,
            alignment: Alignment.center,
            child: Text(
              DateFormat.MMM().format(value),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected
                    ? widget.accent
                    : enabled
                    ? AppPalette.ink(context)
                    : AppPalette.border(context),
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

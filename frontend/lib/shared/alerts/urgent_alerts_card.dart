import 'dart:async';

import 'package:flutter/material.dart';

import '../../doctors/alerts/doctor_alert_resolve_sheet.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/user_role.dart';
import '../navigation/sos_navigation.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import 'alert_center.dart';
import 'urgent_alert_dialog.dart';
import '../widgets/loading/loading.dart';

/// Something worth the strip when nothing is urgent.
///
/// The band used to go quiet the moment the queue cleared — a green panel
/// saying "no urgent items", holding the top of the dashboard to report an
/// absence. A dashboard's best line is never "nothing happened"; these are
/// what the page has to say instead, and they take the same turn in the same
/// strip.
class QuietNote {
  const QuietNote({
    required this.title,
    required this.detail,
    required this.icon,
    required this.accent,
    this.count = 0,
    this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color accent;

  /// Shown on the icon, the way the urgent count is. Zero means no badge.
  final int count;
  final VoidCallback? onTap;
}

/// One turn of the strip, whatever it is speaking for.
///
/// Urgent items and quiet notes are the same shape once they reach the line —
/// a who, a what, an icon, a colour and a count — so the strip rotates one
/// list and does not care which kind it is showing.
class _Announcement {
  const _Announcement({
    required this.id,
    required this.title,
    required this.detail,
    required this.icon,
    required this.accent,
    required this.badge,
    this.value,
    this.status,
    this.onTap,
  });

  final String id;
  final String title;
  final String detail;
  final IconData icon;
  final Color accent;
  final int badge;

  /// The reading behind the alert (`172/108 mmHg`), or where an emergency was
  /// raised. It was already carried on the item and only visible once someone
  /// opened the queue; on the line it is the single most useful thing in the
  /// space to the right of the name. Null when there is nothing to show.
  final String? value;

  /// Whether anyone has taken this on yet. Null for notes that cannot be
  /// owned.
  final String? status;

  final VoidCallback? onTap;
}

/// The urgent queue on the dashboard, as a notification rather than a board.
///
/// This used to be the queue rendered in full: a header, four scrolling rows
/// with two icon buttons each, a primary action and a link — a third of a
/// phone screen, sitting directly above a "Choose a task → Urgent care" tile
/// that goes to the same work. Two surfaces for one job, and the one at the
/// top was the one shouting.
///
/// So it reads the way a notification reads. Collapsed it is one line: the
/// count on the icon, who it is about, what happened, how long ago, and how
/// many are behind it — and it takes turns, so the fifth alert is seen by
/// someone who never opens anything. That line is still live: tapping it
/// works whatever it is currently showing. The chevron expands the same rows
/// and actions that used to be permanently on show.
///
/// When the queue clears the strip does not go blank or turn into a green
/// panel about an absence — it rotates [quiet] instead, so the space keeps
/// earning its place. With nothing at all to say it takes no height.
///
/// While it is mounted it registers with [AlertCenter] as the screen's
/// standing queue surface, so the floating banners stop repeating what this
/// already lists — but an alert that *arrives* while someone is on this page
/// still flies over the top, which is the whole point of a heads-up.
class UrgentAlertsCard extends StatefulWidget {
  const UrgentAlertsCard({
    super.key,
    this.maxRows = 4,
    this.initiallyExpanded = false,
    this.quiet = const [],
  });

  /// Rows shown at once while expanded; the rest are reachable by scrolling.
  final int maxRows;

  /// Opens expanded. The dashboard does not — a standing queue that takes a
  /// third of the screen is what this replaced.
  final bool initiallyExpanded;

  /// What the strip says when nothing is urgent, in turn.
  final List<QuietNote> quiet;

  /// How long each turn holds. Long enough to read a name and a line, short
  /// enough that the last of six is seen inside half a minute.
  static const Duration turn = Duration(seconds: 5);

  @override
  State<UrgentAlertsCard> createState() => _UrgentAlertsCardState();
}

class _UrgentAlertsCardState extends State<UrgentAlertsCard> {
  /// The last queue this card actually drew.
  ///
  /// A session refresh briefly has no data of its own. Rendering that as "no
  /// urgent items outstanding" told an operator with six live alerts — two of
  /// them emergencies — that they had none, then took it back a moment later.
  /// Between "nothing outstanding" and "not loaded yet", only one of those is
  /// safe to assert, so the card keeps showing what it last knew until a
  /// settled refresh proves the queue is genuinely clear.
  List<UrgentItem> _lastKnown = const [];

  late bool _expanded = widget.initiallyExpanded;

  /// Which turn the strip is on. Counts up forever and is taken modulo the
  /// number of announcements, so the queue changing size never lands it on an
  /// index that has gone.
  int _turn = 0;
  Timer? _rotation;

  @override
  void initState() {
    super.initState();
    AlertCenter.instance.registerInlineQueue(this);
  }

  @override
  void dispose() {
    _rotation?.cancel();
    AlertCenter.instance.unregisterInlineQueue(this);
    super.dispose();
  }

  int get maxRows => widget.maxRows;

  /// Start or stop the rotation to match what is on screen.
  ///
  /// Idempotent, and called from build: one item has nothing to rotate to, an
  /// expanded card is already showing everything at once, and a reader who
  /// has asked the platform to stop animating things should not have the line
  /// changing under them either.
  void _syncRotation({required int count, required bool allowed}) {
    final wanted = allowed && !_expanded && count > 1;
    if (!wanted) {
      _rotation?.cancel();
      _rotation = null;
      return;
    }
    _rotation ??= Timer.periodic(UrgentAlertsCard.turn, (_) {
      if (mounted) setState(() => _turn++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AlertCenter.instance,
      builder: (context, _) {
        final live = AlertCenter.instance.openQueue;
        if (live.isNotEmpty) {
          _lastKnown = live;
        } else if (StaffState.instance.isSyncing && _lastKnown.isNotEmpty) {
          // Mid-refresh: hold the picture rather than blanking it.
        } else {
          _lastKnown = const [];
        }

        final queue = live.isEmpty ? _lastKnown : live;
        final urgent = queue.isNotEmpty;

        // Never empty: a clear queue is worth one calm line, and the page's
        // own work takes the turns after it.
        final announcements = urgent
            ? _fromQueue(queue)
            : _fromQuiet(widget.quiet);

        final reduceMotion =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        _syncRotation(count: announcements.length, allowed: !reduceMotion);

        final showing = announcements[_turn % announcements.length];

        final unattended = AlertCenter.instance.unattendedCount;
        final sos = queue.where((i) => i.isSos).length;
        final critical = queue
            .where((i) => i.kind == UrgentKind.criticalVital)
            .length;
        final warning = queue
            .where((i) => i.kind == UrgentKind.warningVital)
            .length;
        final alertsRoute = alertsRouteForCurrentRole();

        // No card. A notification is not a panel — boxing this one put a
        // bordered container round a single line, indented it away from both
        // edges, and stacked it directly above the bordered task cards it is
        // not one of. The badge and the accent carry the urgency; the width
        // is the page's.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NotificationLine(
              showing: showing,
              others: announcements.length - 1,
              position: (_turn % announcements.length) + 1,
              total: announcements.length,
              expanded: _expanded,
              animate: !reduceMotion,
              urgent: urgent,
              // Collapsed, this is the only place the shape of the queue is
              // stated; expanded, _Breakdown says it in full just below, so
              // the line does not repeat itself.
              summary: urgent && !_expanded
                  ? _queueSummary(
                      sos: sos,
                      critical: critical,
                      warning: warning,
                      unattended: unattended,
                    )
                  : null,
              // The chevron always earns its place: it opens the actionable
              // queue during an incident and the compact operational overview
              // while the queue is clear.
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
            // The board, on request. Same rows, same actions, same fixed
            // viewport — just no longer the default state of the page.
            //
            // Built only while it is open. AnimatedCrossFade would keep
            // the whole queue — every row, every action — mounted behind
            // a collapsed line, which is not a collapsed card; it is a
            // hidden one, with all of its cost still paid.
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : urgent
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        _Breakdown(
                          sos: sos,
                          critical: critical,
                          warning: warning,
                          unattended: unattended,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _QueueList(queue: queue, maxRows: maxRows),
                        const SizedBox(height: AppSpacing.sm),
                        AppButton(
                          label: unattended > 0
                              ? 'Work through $unattended unattended'
                              : 'Review ${queue.length} open',
                          icon: AppIcons.alert,
                          variant: unattended > 0
                              ? AppButtonVariant.danger
                              : AppButtonVariant.secondary,
                          expand: true,
                          onPressed: () => _reviewAll(context),
                        ),
                        if (alertsRoute != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _OpenFullListLink(route: alertsRoute),
                        ],
                      ],
                    )
                  : _QuietOverview(
                      announcements: announcements,
                      maxRows: maxRows,
                    ),
            ),
            // The rule the card's border used to be — it separates the
            // queue from the tasks below without enclosing it.
            const _SectionRule(),
          ],
        );
      },
    );
  }

  /// Every outstanding item gets a turn, so the sixth alert is seen by
  /// someone who never expands anything. The badge stays the whole count —
  /// it answers "how much is outstanding", not "which one is this".
  /// What the queue is made of, in the words [_Breakdown] uses when the board
  /// is open — so opening it confirms the line rather than restating it
  /// differently.
  String _queueSummary({
    required int sos,
    required int critical,
    required int warning,
    required int unattended,
  }) => [
    if (sos > 0) '$sos emergency',
    if (critical > 0) '$critical critical',
    if (warning > 0) '$warning warning',
    if (unattended > 0) '$unattended not yet owned' else 'all owned',
  ].join(' · ');

  List<_Announcement> _fromQueue(List<UrgentItem> queue) => [
    for (final item in queue)
      _Announcement(
        id: item.id,
        title: item.patientName,
        detail: '${item.title} · ${_urgentRelativeTime(item.createdAt)}',
        // Ownership used to be a "· owned" tail on the detail line, where it
        // was easy to miss and said nothing when an item was *not* owned.
        // Unowned is the state that needs a responder, so it gets said out
        // loud in its own column.
        value: item.detail.trim().isEmpty ? null : item.detail.trim(),
        status: item.acknowledged ? 'Owned' : 'Not yet owned',
        icon: item.isSos ? AppIcons.sos : AppIcons.alert,
        accent: switch (item.kind) {
          UrgentKind.sos || UrgentKind.criticalVital => AppColors.critical,
          UrgentKind.warningVital => AppColors.warning,
        },
        badge: queue.length,
        onTap: () => _openOne(context, item),
      ),
  ];

  /// A clear queue still says so — once, as the first turn — and then gets on
  /// with what the page actually has waiting.
  List<_Announcement> _fromQuiet(List<QuietNote> notes) => [
    const _Announcement(
      id: 'all-clear',
      title: 'Nothing urgent outstanding',
      detail: 'Your scope is clear',
      icon: AppIcons.check,
      accent: AppColors.success,
      badge: 0,
    ),
    for (final note in notes)
      _Announcement(
        id: 'quiet:${note.title}',
        title: note.title,
        detail: note.detail,
        icon: note.icon,
        accent: note.accent,
        badge: note.count,
        onTap: note.onTap,
      ),
  ];

  /// Work the one the strip is currently showing — not the top of the queue.
  /// A line that names an alert and then opens a different one is a line that
  /// cannot be trusted.
  Future<void> _openOne(BuildContext context, UrgentItem item) async {
    AlertCenter.instance.forceDue([item.id]);
    await UrgentAlertDialog.showQueue(context, [item]);
  }

  /// Force the queue to surface now, even for items currently snoozed or
  /// still inside their escalation backoff.
  ///
  /// Unowned items come first because that is what the button offers to work
  /// through; when everything is already owned but still open, "review" walks
  /// the whole open queue rather than reporting nothing to do.
  Future<void> _reviewAll(BuildContext context) async {
    final center = AlertCenter.instance;
    final unattended = center.popQueue;
    final queue = unattended.isNotEmpty ? unattended : center.openQueue;
    if (queue.isEmpty) {
      AppToast.info(context, 'Nothing outstanding — the queue is clear.');
      return;
    }
    center.forceDue(queue.map((i) => i.id));
    await UrgentAlertDialog.showQueue(context, queue);
  }
}

/// The collapsed state, and the header of the expanded one.
///
/// It says what a phone notification says — who, what, when, how many — and
/// then fills the rest of its own width rather than leaving it blank: the
/// reading that triggered the alert, whether anyone owns it yet, and what the
/// queue behind it is made of. All of it was already loaded and none of it
/// was on screen until someone opened the queue.
///
/// The band is a fixed height either way. These sit in space the line was
/// already holding, so nothing below it moves.
///
/// Tapping the text works what it is showing; the chevron is the only control
/// that merely changes what is on screen.
class _NotificationLine extends StatelessWidget {
  const _NotificationLine({
    required this.showing,
    required this.others,
    required this.position,
    required this.total,
    required this.expanded,
    required this.animate,
    required this.urgent,
    required this.onToggle,
    this.summary,
  });

  final _Announcement showing;

  /// How many more are waiting their turn.
  final int others;
  final int position;
  final int total;
  final bool expanded;
  final bool animate;
  final bool urgent;

  /// What the whole queue is made of, e.g. `1 emergency · 4 critical`. Shown
  /// collapsed, where the expanded board's breakdown is not on screen.
  final String? summary;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = showing.accent;
    final muted = AppPalette.textMuted(context);
    final value = showing.value;
    final status = showing.status;
    final summaryLine = summary;

    final body = Row(
      key: ValueKey(showing.id),
      children: [
        _CountBadge(icon: showing.icon, accent: accent, count: showing.badge),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      showing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    // A bare reading is short, but the field also arrives
                    // carrying advisory prose ("172/108 mmHg — immediate
                    // review required"), and an emergency puts its location
                    // and note here. Unbounded, any of those burst the row.
                    //
                    // Who it is about outranks what the reading said, so the
                    // name keeps three parts of the row to the reading's two
                    // and the reading ellipsises rather than squeezing the
                    // patient off the line.
                    Flexible(
                      flex: 2,
                      child: _ReadingChip(value: value, accent: accent),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      showing.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (status != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    // Kept to one line: wrapping here would grow the band and
                    // push the whole dashboard down.
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
              if (summaryLine != null)
                Text(
                  summaryLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
            ],
          ),
        ),
        if (urgent && others > 0 && !expanded)
          Container(
            margin: const EdgeInsets.only(left: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              '+$others',
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );

    // This consumes the section's former top/bottom whitespace instead of
    // introducing a new surface or growing the dashboard. The result reads as
    // a full-width information stage, not a thin card floating inside it.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          // Everything but the chevron is the tap target: on a bare line there
          // is no card edge to aim at, so the target is the line itself.
          Expanded(
            child: Semantics(
              button: showing.onTap != null,
              liveRegion: true,
              label: [
                showing.title,
                showing.detail,
                ?value,
                ?status,
                ?summaryLine,
              ].join('. '),
              child: InkWell(
                onTap: showing.onTap,
                child: Padding(
                  // Tightened as the line gained rows, so the band keeps the
                  // height it already had rather than pushing the page down.
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  // Turns cross-fade in place, so the line never jumps and the
                  // page below it never moves.
                  child: animate
                      ? AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeIn,
                          layoutBuilder: (current, previous) => Stack(
                            alignment: Alignment.centerLeft,
                            children: [...previous, ?current],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.35),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: body,
                        )
                      : body,
                ),
              ),
            ),
          ),
          if (!urgent && total > 1 && !expanded)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                '$position/$total',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          IconButton(
            tooltip: expanded
                ? 'Collapse'
                : urgent
                ? 'Show all ${others + 1}'
                : 'Show dashboard overview',
            onPressed: onToggle,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            icon: Icon(
              expanded ? AppIcons.expandLess : AppIcons.expandMore,
              size: 20,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// A hairline under the queue, in place of the border that used to go round
/// it. It marks where the notification ends and the page's own work begins.
class _SectionRule extends StatelessWidget {
  const _SectionRule();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: Divider(height: 1, thickness: 1, color: AppPalette.border(context)),
  );
}

/// The non-urgent counterpart to the queue board.
///
/// It gives the persistent chevron a useful, honest destination and caps its
/// viewport at [maxRows], so even a rich admin snapshot cannot push the task
/// grid arbitrarily far down the page. Like the collapsed stage, it is drawn
/// directly on the page rather than inside another card.
class _QuietOverview extends StatefulWidget {
  const _QuietOverview({required this.announcements, required this.maxRows});

  final List<_Announcement> announcements;
  final int maxRows;

  @override
  State<_QuietOverview> createState() => _QuietOverviewState();
}

class _QuietOverviewState extends State<_QuietOverview> {
  static const double _rowExtent = 44;
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.announcements;
    final visibleRows = items.length.clamp(1, widget.maxRows).toInt();
    final scrolls = items.length > widget.maxRows;

    final list = ListView.builder(
      controller: _controller,
      physics: scrolls
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemExtent: _rowExtent,
      itemCount: items.length,
      itemBuilder: (context, index) => _QuietOverviewRow(item: items[index]),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SizedBox(
        height: visibleRows * _rowExtent,
        child: scrolls
            ? Scrollbar(
                controller: _controller,
                thumbVisibility: true,
                child: list,
              )
            : list,
      ),
    );
  }
}

class _QuietOverviewRow extends StatelessWidget {
  const _QuietOverviewRow({required this.item});

  final _Announcement item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: item.onTap != null,
      label: '${item.title}. ${item.detail}.',
      child: InkWell(
        onTap: item.onTap,
        child: Row(
          children: [
            Icon(item.icon, size: 16, color: item.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    item.detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (item.badge > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${item.badge}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: item.accent,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
            if (item.onTap != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                AppIcons.chevronRight,
                size: 17,
                color: AppPalette.textMuted(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The reading that triggered the alert, sat at the end of the name row.
///
/// It reads as a measurement rather than a control: no border, no tap target,
/// tabular figures so a column of them does not jitter as the strip rotates.
class _ReadingChip extends StatelessWidget {
  const _ReadingChip({required this.value, required this.accent});

  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          height: 1.2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.accent,
    required this.count,
  });

  final IconData icon;
  final Color accent;
  final int count;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      width: 38,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 34,
            width: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          if (count > 0)
            Positioned(
              right: 0,
              top: -2,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  border: Border.all(
                    color: AppPalette.surface(context),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the queue is made of — only worth the line once someone has asked to
/// see the whole thing.
class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.sos,
    required this.critical,
    required this.warning,
    required this.unattended,
  });

  final int sos;
  final int critical;
  final int warning;
  final int unattended;

  @override
  Widget build(BuildContext context) {
    return Text(
      [
        if (sos > 0) '$sos emergency',
        if (critical > 0) '$critical critical',
        if (warning > 0) '$warning warning',
        if (unattended > 0) '$unattended not yet owned' else 'all owned',
      ].join(' · '),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: AppPalette.textMuted(context),
        fontSize: 10.5,
      ),
    );
  }
}

/// The queue rows, in a viewport that holds its height.
///
/// The card used to render four rows and hide the rest behind "+2 more
/// outstanding", so its height changed with every alert that arrived or was
/// resolved — the dashboard below it moved under the operator's thumb, and
/// two of six alerts were only reachable by opening the popup. Now the rows
/// live in a fixed viewport sized to [maxRows]: every alert is reachable by
/// scrolling, and the card occupies the same space whether there are two or
/// twenty.
class _QueueList extends StatefulWidget {
  const _QueueList({required this.queue, required this.maxRows});

  final List<UrgentItem> queue;
  final int maxRows;

  /// One row: the severity rail is 34 high inside `AppSpacing.xs` padding
  /// top and bottom.
  static const double rowExtent = 34 + AppSpacing.xs * 2;

  @override
  State<_QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<_QueueList> {
  /// Its own controller, not the primary one: this list lives inside the
  /// dashboard's scroll view, so there is no primary controller to borrow and
  /// a visible thumb needs one of its own.
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    final scrolls = queue.length > widget.maxRows;
    final height =
        _QueueList.rowExtent * (scrolls ? widget.maxRows : queue.length);

    final list = ListView.builder(
      controller: _controller,
      // A list that fits must not swallow the page's scroll gesture.
      physics: scrolls
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemExtent: _QueueList.rowExtent,
      itemCount: queue.length,
      itemBuilder: (context, i) =>
          _UrgentRow(key: ValueKey(queue[i].id), item: queue[i]),
    );

    return SizedBox(
      height: height,
      child: scrolls
          ? Scrollbar(
              controller: _controller,
              thumbVisibility: true,
              child: list,
            )
          : list,
    );
  }
}

/// The full alerts list for whoever is signed in, or null for a role that has
/// no such screen. Kept here so the card and its rows agree on one answer.
String? alertsRouteForCurrentRole() => switch (AuthState.instance.user?.role) {
  UserRole.admin => RouteNames.adminAlerts,
  UserRole.mcareAssistant => RouteNames.assistantAlerts,
  UserRole.doctor => RouteNames.doctorAlerts,
  _ => null,
};

/// Escape hatch to the complete alerts screen — including acknowledged and
/// already-resolved items, which the urgent queue deliberately drops.
class _OpenFullListLink extends StatelessWidget {
  const _OpenFullListLink({required this.route});

  final String route;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => Navigator.of(
        context,
      ).pushNamed(route, arguments: AlertsListFilter.all),
      icon: const Icon(AppIcons.records, size: 16),
      label: const Text('Open all alerts'),
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.textMuted(context),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        minimumSize: const Size.fromHeight(36),
      ),
    );
  }
}

/// Route argument understood by the staff alerts screens.
class AlertsListFilter {
  const AlertsListFilter._();

  /// Show everything, not just what is still open.
  static const String all = 'all';
}

class _UrgentRow extends StatefulWidget {
  const _UrgentRow({super.key, required this.item});
  final UrgentItem item;

  @override
  State<_UrgentRow> createState() => _UrgentRowState();
}

class _UrgentRowState extends State<_UrgentRow> {
  bool _busy = false;

  Future<void> _acknowledge() async {
    final item = widget.item;
    setState(() => _busy = true);
    try {
      final ok = item.alert != null
          ? await StaffState.instance.acknowledgeAlert(item.alert!.id)
          : await StaffState.instance.updateSosForCurrentRole(
              item.sos!.id,
              status: 'acknowledged',
            );
      if (!mounted) return;
      if (ok) {
        AppToast.success(
          context,
          'Acknowledged — this stays open until resolved.',
        );
      } else {
        AppToast.error(context, 'Could not acknowledge — try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Open this one item in the full urgent card — care team, three-day
  /// vitals context and every action — rather than only the two icon
  /// shortcuts the row has room for.
  Future<void> _openDetail() async {
    final item = widget.item;
    AlertCenter.instance.forceDue([item.id]);
    await UrgentAlertDialog.showQueue(context, [item]);
  }

  Future<void> _resolve() async {
    final item = widget.item;
    setState(() => _busy = true);
    try {
      if (item.alert != null) {
        await DoctorAlertResolveFlow.resolve(context, item.alert!);
      } else {
        await SosNavigation.openRespond(
          context,
          patientId: item.patientId,
          eventId: item.sos!.id,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final accent = switch (item.kind) {
      UrgentKind.sos || UrgentKind.criticalVital => AppColors.critical,
      UrgentKind.warningVital => AppColors.warning,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: InkWell(
              onTap: _busy ? null : _openDetail,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (item.acknowledged) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusPill,
                            ),
                          ),
                          child: const Text(
                            'OWNED',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${item.title}${item.detail.isEmpty ? '' : ' · ${item.detail}'}'
                    ' · ${_urgentRelativeTime(item.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (_busy)
            const McarePulse(size: McarePulseSize.micro, semanticLabel: null)
          else ...[
            if (!item.acknowledged)
              IconButton(
                tooltip: 'Acknowledge',
                onPressed: _acknowledge,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 40,
                  height: 40,
                ),
                icon: const Icon(
                  AppIcons.acknowledge,
                  size: 17,
                  color: AppColors.info,
                ),
              ),
            IconButton(
              tooltip: item.isSos ? 'Respond to SOS' : 'Resolve',
              onPressed: _resolve,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: Icon(AppIcons.check, size: 17, color: accent),
            ),
          ],
        ],
      ),
    );
  }
}

String _urgentRelativeTime(DateTime at) {
  final difference = DateTime.now().difference(at);
  if (difference.inMinutes < 1) return 'now';
  if (difference.inHours < 1) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  return '${difference.inDays}d';
}

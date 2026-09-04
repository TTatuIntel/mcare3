part of 'patient_dashboard_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "For you" — the patient's live stream.
//
// One list, one job: everything the app knows about this patient right now,
// ordered so the answer to "what changed, and what still needs me?" is the
// first thing on screen. The rows are built from the same scenes the briefing
// at the top of the page reads, so the two surfaces can never disagree, and
// the feed owns two rules the briefing does not:
//
//   1. Ranking      live work first — alerts, then reminders by how soon they
//                   are due, then updates newest-first; under it the things
//                   nobody has picked up yet; under those the finished ones,
//                   newest first; and the quiet tally last of all.
//   2. De-duplication  the same underlying thing is never listed twice, no
//                   matter how many stores mention it.
//   3. Depth        a short stream is on the page. A long one becomes a
//                   window the patient scrolls inside, so the page below it
//                   stays where they left it.
//
// Nothing here moves on its own: there is no timer and no carousel. Past
// [_forYouWindowRows] rows the stream stops growing the page and scrolls
// inside a fixed window instead — the patient's own thumb is still the only
// thing that moves it.
// ─────────────────────────────────────────────────────────────────────────────

/// What a row is asking of the patient. The order of the constants is the
/// order of the feed: this enum *is* the ranking policy.
enum _FeedKind {
  /// Something is wrong now.
  alert('Alert'),

  /// Something is expected of the patient, at a known time.
  reminder('Reminder'),

  /// Something happened; nothing is being asked.
  update('Update'),

  /// A counted summary of the day. Reports, never asks.
  insight('Summary');

  const _FeedKind(this.label);

  final String label;

  /// Higher sorts first.
  int get weight => _FeedKind.values.length - index;
}

/// One row of the stream.
///
/// [key] is the identity of the *thing* — a dose, a document, a ticket — so
/// two stores describing the same event collapse into one row. [at] is when
/// it happened for an [_FeedKind.update], and when it is due for an
/// [_FeedKind.reminder]; the sort reads it differently for each.
class _FeedItem {
  const _FeedItem({
    required this.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.at,
    required this.rank,
    this.body,
    this.urgent = false,
    this.stage = _SceneStage.open,
    this.onTap,
  });

  final String key;
  final _FeedKind kind;
  final String title;
  final String subtitle;
  final String? body;
  final IconData icon;
  final Color accent;
  final DateTime at;

  /// Tie-break inside a kind, carried over from the scene's priority.
  final int rank;

  final bool urgent;

  /// Carried straight from the scene: whether anyone is still acting on this.
  final _SceneStage stage;

  final VoidCallback? onTap;

  /// Two rows that read identically are the same row, even when they were
  /// built from different stores under different ids.
  String get signature =>
      '${title.trim()}|${subtitle.trim()}|${(body ?? '').trim()}'.toLowerCase();

  /// Recent enough that the patient has probably not seen it yet.
  bool isNew(DateTime now) =>
      kind != _FeedKind.insight &&
      !at.isAfter(now) &&
      now.difference(at) < const Duration(hours: 3);
}

/// Classifies a hub scene. Scene ids are stable and already unique per
/// entity, so they carry both the kind and the de-duplication key.
_FeedKind _feedKindOf(_HubScene scene) {
  if (scene.id.startsWith('sos_') || scene.id.startsWith('alert_')) {
    return _FeedKind.alert;
  }
  // A late dose is a reminder that happens to be urgent, not an alarm: the
  // urgency moves it up its own group instead of renaming it.
  if (scene.id.startsWith('meds_') ||
      scene.id.startsWith('appt_') ||
      scene.id == 'profile') {
    return _FeedKind.reminder;
  }
  if (scene.id == 'progress') return _FeedKind.insight;
  return scene.urgent ? _FeedKind.alert : _FeedKind.update;
}

/// Builds the ordered, de-duplicated stream.
///
/// Everything comes from [_buildHubScenes] — the feed invents no facts of its
/// own — plus the one standing reminder that is a step rather than a scene:
/// today's vitals.
///
/// One scene is dropped on the way in: `updates` is a count of the
/// notification centre that the app bar's bell already shows. The count is
/// offered as the section's action instead, so it appears exactly once on the
/// screen.
List<_FeedItem> _buildFeed(
  BuildContext context, {
  required List<Appointment> appointments,
  required List<MedicationDose> doses,
  required int unreadNotifications,
}) {
  final now = DateTime.now();
  final items = <_FeedItem>[];

  for (final scene in _buildHubScenes(
    context,
    appointments: appointments,
    doses: doses,
    unreadNotifications: unreadNotifications,
  )) {
    if (scene.id == 'updates') continue;
    items.add(
      _FeedItem(
        key: scene.id,
        kind: _feedKindOf(scene),
        title: scene.title,
        subtitle: scene.subtitle,
        body: scene.body,
        icon: scene.icon,
        accent: scene.accent,
        at: scene.at,
        rank: scene.priority,
        urgent: scene.urgent,
        stage: scene.stage,
        onTap: scene.actions.isEmpty ? null : scene.actions.first.onTap,
      ),
    );
  }

  // Today's vitals: a step, not a scene, so the stream has to add it itself.
  final tracked = VitalsState.instance.tracked.toList();
  if (tracked.isNotEmpty) {
    final outstanding = tracked
        .where(
          (key) => !DateUtils.isSameDay(
            VitalsState.instance.latestOf(key)?.recordedAt,
            now,
          ),
        )
        .toList();
    if (outstanding.isNotEmpty) {
      final next = outstanding.first;
      items.add(
        _FeedItem(
          key: 'reminder_vitals',
          kind: _FeedKind.reminder,
          title: outstanding.length == 1
              ? 'Log your ${next.label.toLowerCase()}'
              : 'Log today\'s vitals',
          subtitle: outstanding.length == 1
              ? 'Not recorded today'
              : '${outstanding.length} of ${tracked.length} still to record',
          body: 'Your care team reads today\'s numbers, not last week\'s.',
          icon: next.icon,
          accent: AppColors.brandIndigo,
          at: now,
          rank: 40,
          onTap: () => SubmitVitalSheet.show(context, initial: next),
        ),
      );
    }
  }

  // De-duplicate on both identity and wording, keeping the first occurrence —
  // scenes arrive in priority order, so the richest version of a thing wins.
  final seenKeys = <String>{};
  final seenText = <String>{};
  final unique = <_FeedItem>[
    for (final item in items)
      if (seenKeys.add(item.key) && seenText.add(item.signature)) item,
  ];

  unique.sort((a, b) {
    final byBand = _feedBand(a).compareTo(_feedBand(b));
    if (byBand != 0) return byBand;

    // Waiting, finished and counted rows are all answers to "when?", so date
    // is the whole of their order: the latest first, oldest last.
    if (_feedBand(a) > _feedBand0) {
      final byDate = b.at.compareTo(a.at);
      if (byDate != 0) return byDate;
      return b.rank.compareTo(a.rank);
    }

    final byKind = b.kind.weight.compareTo(a.kind.weight);
    if (byKind != 0) return byKind;
    // Reminders read forwards — most overdue first, then soonest due.
    // Everything else reads backwards — the latest first.
    if (a.kind == _FeedKind.reminder) {
      final byDue = a.at.compareTo(b.at);
      if (byDue != 0) return byDue;
    } else {
      final byRecency = b.at.compareTo(a.at);
      if (byRecency != 0) return byRecency;
    }
    return b.rank.compareTo(a.rank);
  });

  return unique;
}

/// The band of live work — everything somebody can still act on.
const int _feedBand0 = 0;

/// Which band of the stream a row belongs to. Lower reads first.
///
/// This is the ordering the patient asked for, in one function: what is
/// happening now, then what has been sent and not picked up, then what is
/// finished, and last the tally that only counts. Ranking *within* a band is
/// the kind order above; nothing in a later band can outrank anything in an
/// earlier one, so a resolved alert cannot climb over a dose that is due.
int _feedBand(_FeedItem item) {
  // The day's tally reports and never asks, so it closes the stream whatever
  // its stage says.
  if (item.kind == _FeedKind.insight) return 3;
  return switch (item.stage) {
    _SceneStage.open => _feedBand0,
    _SceneStage.waiting => 1,
    _SceneStage.closed => 2,
  };
}

/// How many rows the stream will lay out on the page before it becomes a
/// window of its own.
///
/// Thirteen is the point where the feed stops being a list the patient reads
/// and becomes a page they have to work through. Up to there it sits on the
/// page like any other section. Past it the stream keeps every row — nothing
/// is hidden behind a control any more — but it holds them in a fixed window
/// the patient scrolls, so a busy week cannot turn home into a long page.
const int _forYouWindowRows = 13;

/// How tall that window stands, as a share of the screen, and the bounds that
/// keep it sensible on a small phone and on a desktop.
///
/// Sized from the screen rather than from a row count on purpose: thirteen
/// rows is taller than the phone they are read on, and a window taller than
/// the screen is not a window.
const double _forYouWindowFraction = 0.62;
const double _forYouWindowMinHeight = 320;
const double _forYouWindowMaxHeight = 720;

/// The stream itself, listed straight onto the page background.
///
/// It once scrolled itself a row at a time, on a timer. Two things moved
/// under the reader at once — this and the hub above it — and the page could
/// not be used while they did. Nothing here moves on its own any more: the
/// only thing that scrolls this list is the patient's own thumb.
///
/// A short stream rides the page's scroll, exactly as any other section does.
/// A long one — more than [_forYouWindowRows] rows — becomes a window: every
/// row is still in it, but the section stops growing past a screenful, so the
/// rest of the page stays within reach of the thumb that got there.
class _PatientForYouSection extends StatefulWidget {
  const _PatientForYouSection({
    required this.appointments,
    required this.doses,
    required this.unreadNotifications,
  });

  final List<Appointment> appointments;
  final List<MedicationDose> doses;
  final int unreadNotifications;

  @override
  State<_PatientForYouSection> createState() => _PatientForYouSectionState();
}

class _PatientForYouSectionState extends State<_PatientForYouSection> {
  /// The window's own scroller. Held here rather than in the window widget so
  /// that a rebuild — a new reading, a message read — does not throw the
  /// patient back to the top of a list they were part-way down.
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        MessagesState.instance,
        AnnouncementsState.instance,
        MealPlansState.instance,
        DocumentsState.instance,
        SupportState.instance,
        VitalReportState.instance,
        SosState.instance,
        ProfileState.instance,
      ]),
      builder: (context, _) {
        final items = _buildFeed(
          context,
          appointments: widget.appointments,
          doses: widget.doses,
          unreadNotifications: widget.unreadNotifications,
        );
        final now = DateTime.now();

        final total = items.length;
        // Past the window size the stream holds its own rows instead of
        // handing them to the page.
        final windowed = total > _forYouWindowRows;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              title: 'For you',
              icon: AppIcons.activity,
              trailing: items.isEmpty
                  ? null
                  : '$total update${total == 1 ? '' : 's'}',
              actionLabel: widget.unreadNotifications > 0 ? 'Inbox' : null,
              onAction: widget.unreadNotifications > 0
                  ? () => Navigator.of(
                      context,
                    ).pushNamed(RouteNames.patientNotifications)
                  : null,
            ),
            if (items.isEmpty)
              EmptyStateView(
                icon: AppIcons.check,
                title: 'You are all caught up',
                message:
                    'New care updates and recommendations will appear here.',
                actionLabel: 'Log a vital',
                onAction: () => SubmitVitalSheet.show(context),
                compact: true,
              )
            else if (windowed)
              _ForYouWindow(controller: _controller, items: items, now: now)
            else
              for (var i = 0; i < total; i++)
                _FeedRow(item: items[i], now: now, showDivider: i != total - 1),
          ],
        );
      },
    );
  }
}

/// The stream when it is longer than the page should be.
///
/// A window of its own, sized from the screen, holding every row the feed
/// built. Nothing is hidden and nothing is behind a control: the tail is
/// reached the way anything else on a phone is reached, by scrolling — only
/// the scrolling happens here rather than lengthening the page under it.
///
/// The window is deliberately not a card. The rows keep sitting on the page
/// background exactly as they do when the stream is short, so the change at
/// thirteen rows is a change of depth, not of design. The scrollbar stays
/// visible because the only cue that a list continues is a row cut off at the
/// edge, and a cut-off row on a plain background can read as the end.
class _ForYouWindow extends StatelessWidget {
  const _ForYouWindow({
    required this.controller,
    required this.items,
    required this.now,
  });

  final ScrollController controller;
  final List<_FeedItem> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * _forYouWindowFraction)
        .clamp(_forYouWindowMinHeight, _forYouWindowMaxHeight)
        .toDouble();

    return SizedBox(
      height: height,
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: ListView.builder(
          controller: controller,
          // Never the page's scroller: this list owns its own, and taking the
          // primary one would move the whole page instead.
          primary: false,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(right: AppSpacing.md),
          itemCount: items.length,
          itemBuilder: (context, i) => _FeedRow(
            item: items[i],
            now: now,
            showDivider: i != items.length - 1,
          ),
        ),
      ),
    );
  }
}

/// One row, on the background. It grows with what it holds — the window
/// above scrolls rather than squeezing — so a long subtitle wraps to its two
/// lines instead of being cut to fit a fixed height.
class _FeedRow extends StatelessWidget {
  const _FeedRow({
    required this.item,
    required this.now,
    required this.showDivider,
  });

  final _FeedItem item;
  final DateTime now;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PatientIconDisc(icon: item.icon, color: item.accent, size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _FeedKindChip(item: item),
                    if (item.isNew(now)) ...[
                      const SizedBox(width: 6),
                      Container(
                        height: 6,
                        width: 6,
                        decoration: BoxDecoration(
                          color: item.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
                if ((item.body ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppPalette.ink(context),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (item.onTap != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Icon(AppIcons.chevronRight, color: item.accent, size: 20),
            ),
          ],
        ],
      ),
    );

    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        body,
        if (showDivider) Divider(height: 1, color: AppPalette.border(context)),
      ],
    );

    // A row that only reports something carries no ink and no button role.
    if (item.onTap == null) return row;
    return Semantics(
      button: true,
      label: '${item.kind.label}. ${item.title}. ${item.subtitle}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: item.onTap, child: row),
      ),
    );
  }
}

class _FeedKindChip extends StatelessWidget {
  const _FeedKindChip({required this.item});

  final _FeedItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: item.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        item.kind.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: item.accent,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

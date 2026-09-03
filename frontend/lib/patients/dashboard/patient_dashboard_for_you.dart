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
//   1. Ranking      alerts, then reminders by how soon they are due, then
//                   updates newest-first, then the quiet tallies.
//   2. De-duplication  the same underlying thing is never listed twice, no
//                   matter how many stores mention it.
//   3. Depth        the first page of rows is on screen; the tail is one tap
//                   below it, never a scroll the patient did not ask for.
//
// Nothing here moves on its own. The stream has no scroller of its own and no
// timer — it rides the page's scroll, and the only control on it is the one
// that reveals the next page of rows.
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

/// How many rows the stream puts on the page before it starts asking.
///
/// Thirteen is the point where the feed stops being a list the patient reads
/// and becomes a page they have to work through: it covers a phone screen
/// several times over, and everything past it is, by the ranking above,
/// already the least urgent thing the app knows. Anything beyond is still
/// here — it is just one tap away instead of one long scroll away.
const int _forYouPageSize = 13;

/// The stream itself, listed straight onto the page background.
///
/// It used to be a fixed window inside a card that scrolled itself a row at a
/// time. Two things moved under the reader at once — this and the hub above
/// it — and the page could not be used while they did. So the stream still
/// has no scroller of its own: it rides the page's, and the only thing that
/// moves it is the patient's own thumb.
///
/// What it does own is a limit. The first [_forYouPageSize] rows are on the
/// page; the rest are revealed a page at a time, and can be folded back in
/// one tap — which returns the reader to the top of the section rather than
/// leaving them stranded wherever the collapse happened to end.
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
  /// How many rows the patient has asked to see. Never read directly against
  /// the feed — it can exceed a feed that shrank while it was expanded.
  int _visible = _forYouPageSize;

  void _showMore() => setState(() => _visible += _forYouPageSize);

  void _showLess() {
    setState(() => _visible = _forYouPageSize);
    // Collapsing removes rows the reader may be standing on, so take them
    // back to the section header instead of dropping them mid-page.
    if (Scrollable.maybeOf(context) != null) {
      Scrollable.ensureVisible(
        context,
        alignment: 0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
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
        final shown = _visible < total ? _visible : total;
        final remaining = total - shown;
        final nextBatch = remaining < _forYouPageSize
            ? remaining
            : _forYouPageSize;
        final canCollapse = remaining == 0 && total > _forYouPageSize;
        final hasFooter = remaining > 0 || canCollapse;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              title: 'For you',
              icon: AppIcons.activity,
              trailing: items.isEmpty
                  ? null
                  : remaining > 0
                  ? '$shown of $total'
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
            else ...[
              for (var i = 0; i < shown; i++)
                _FeedRow(
                  item: items[i],
                  now: now,
                  showDivider: hasFooter || i != shown - 1,
                ),
              if (remaining > 0)
                _FeedMoreButton(
                  label: 'Show $nextBatch more',
                  // Only worth saying when the batch is not the whole tail.
                  detail: remaining > nextBatch ? '$remaining left' : null,
                  icon: AppIcons.expandMore,
                  onTap: _showMore,
                )
              else if (canCollapse)
                _FeedMoreButton(
                  label: 'Show less',
                  detail: 'showing all $total',
                  icon: AppIcons.expandLess,
                  onTap: _showLess,
                ),
            ],
          ],
        );
      },
    );
  }
}

/// The one control the stream owns: what is left, and the tap that reveals it.
///
/// It is a row like any other row so the list does not appear to end before
/// it — the count sits next to the label rather than under it, because the
/// question it answers ("is it worth going on?") is asked in the same glance.
class _FeedMoreButton extends StatelessWidget {
  const _FeedMoreButton({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String? detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    detail!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(icon, size: 18, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row, on the background. It grows with what it holds — there is no
/// window to fit any more — so a long subtitle wraps instead of being cut.
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

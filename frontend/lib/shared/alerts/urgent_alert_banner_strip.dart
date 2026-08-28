part of 'urgent_alert_banner.dart';

/// The queue as one strip, not a stack of cards.
///
/// What used to float here was a full notification card per item plus a
/// separate "+N more waiting" chip below it — two elements, ~130px of the
/// screen, sitting over the page and, on a dashboard, over a second copy of
/// the same queue. A responder does not need the alert rendered twice; they
/// need to know something is waiting, which one is worst, how many there are,
/// and where to tap.
///
/// So: one line. Severity, who, what, how many, and a way in. Everything else
/// lives one tap away in the queue itself, where there is room for it.
class _BannerStack extends StatelessWidget {
  const _BannerStack({
    required this.ids,
    required this.onOpen,
    required this.onDismiss,
  });

  final List<String> ids;
  final Future<void> Function(List<UrgentItem>) onOpen;
  final void Function(String) onDismiss;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AlertCenter.instance,
      builder: (context, _) {
        final live = {
          for (final item in AlertCenter.instance.openQueue) item.id: item,
        };
        final items = <UrgentItem>[
          for (final id in ids)
            if (live[id] != null) live[id]!,
        ];
        if (items.isEmpty) return const SizedBox.shrink();

        final handheld = ResponsiveBuilder.of(context).isHandheld;

        return Align(
          alignment: handheld ? Alignment.topCenter : Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _AlertStrip(
                // Already sorted worst-first by the layer above; the strip
                // speaks for the one that matters and counts the rest.
                lead: items.first,
                waiting: items.length - 1,
                onOpen: () => onOpen(items),
                onDismiss: () => onDismiss(items.first.id),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One line: severity, who, what, how many are behind it, and a way in.
class _AlertStrip extends StatefulWidget {
  const _AlertStrip({
    required this.lead,
    required this.waiting,
    required this.onOpen,
    required this.onDismiss,
  });

  final UrgentItem lead;

  /// How many more are queued behind [lead].
  final int waiting;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  State<_AlertStrip> createState() => _AlertStripState();
}

class _AlertStripState extends State<_AlertStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    _entry.forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  Color get _accent => switch (widget.lead.kind) {
    UrgentKind.sos => AppColors.critical,
    UrgentKind.criticalVital => AppColors.critical,
    UrgentKind.warningVital => AppColors.warning,
  };

  IconData get _icon => widget.lead.isSos ? AppIcons.sos : AppIcons.alert;

  String get _kindLabel => switch (widget.lead.kind) {
    UrgentKind.sos => 'EMERGENCY',
    UrgentKind.criticalVital => 'CRITICAL',
    UrgentKind.warningVital => 'WARNING',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.lead;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final waiting = widget.waiting;

    final strip = Semantics(
      button: true,
      liveRegion: true,
      label: waiting == 0
          ? '$_kindLabel. ${item.patientName}. ${item.title}. '
                'Double tap to work it.'
          : '$_kindLabel. ${item.patientName}. ${item.title}. '
                'And $waiting more waiting. Double tap to work the queue.',
      child: Material(
        color: AppPalette.surface(context),
        elevation: 8,
        shadowColor: _accent.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: _accent.withValues(alpha: 0.42)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Row(
              children: [
                Container(
                  height: 30,
                  width: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 16, color: _accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.patientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        Text(
                          item.acknowledged
                              ? '${item.title} · owned'
                              : item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: _accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // The count is the whole of the old "+N more waiting" chip,
                // folded into the line it was floating under.
                if (waiting > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                    ),
                    child: Text(
                      '+$waiting',
                      style: TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                Icon(AppIcons.chevronRight, size: 16, color: _accent),
                IconButton(
                  tooltip: 'Remind me in 5 minutes',
                  onPressed: widget.onDismiss,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  iconSize: 15,
                  color: AppPalette.textMuted(context),
                  icon: const Icon(AppIcons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Swiping it aside defers — the same as the × control, and never the same
    // as attending to it.
    final dismissible = Dismissible(
      key: ValueKey('urgent-strip-${item.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => widget.onDismiss(),
      child: strip,
    );

    if (reduceMotion) return dismissible;

    final curved = CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.25),
          end: Offset.zero,
        ).animate(curved),
        child: dismissible,
      ),
    );
  }
}

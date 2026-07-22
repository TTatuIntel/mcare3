part of 'patient_dashboard_view.dart';

class _RecentVitalsPanel extends StatefulWidget {
  const _RecentVitalsPanel();

  @override
  State<_RecentVitalsPanel> createState() => _RecentVitalsPanelState();
}

class _RecentVitalsPanelState extends State<_RecentVitalsPanel> {
  static const _pairHeight = 148.0;

  final _pageController = PageController();
  Timer? _autoPageTimer;
  Timer? _resumeTimer;
  bool _userInteracting = false;
  int _pageIndex = 0;
  int _lastPairCount = 0;

  @override
  void dispose() {
    _autoPageTimer?.cancel();
    _resumeTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  DateTime? _newestReadingAt(List<VitalKey> tracked) {
    DateTime? newest;
    for (final vital in tracked) {
      final reading = VitalsState.instance.latestOf(vital);
      if (reading == null) continue;
      if (newest == null || reading.recordedAt.isAfter(newest)) {
        newest = reading.recordedAt;
      }
    }
    return newest;
  }

  List<VitalKey> _sortedTracked(List<VitalKey> tracked) {
    int priority(VitalKey key) {
      final alert = NotificationState.instance.vitalAlertFor(key);
      if (alert != null) return 0;
      final risk = VitalsState.instance.latestOf(key)?.risk;
      if (risk == RiskLevel.critical) return 1;
      if (risk == RiskLevel.warning) return 2;
      return 3;
    }

    final sorted = tracked.toList()
      ..sort((a, b) {
        final byPriority = priority(a).compareTo(priority(b));
        if (byPriority != 0) return byPriority;
        final ra = VitalsState.instance.latestOf(a)?.recordedAt;
        final rb = VitalsState.instance.latestOf(b)?.recordedAt;
        if (ra == null && rb == null) return 0;
        if (ra == null) return 1;
        if (rb == null) return -1;
        return rb.compareTo(ra);
      });
    return sorted;
  }

  List<List<VitalKey>> _pairs(List<VitalKey> sorted) {
    final pairs = <List<VitalKey>>[];
    for (var i = 0; i < sorted.length; i += 2) {
      final end = (i + 2).clamp(0, sorted.length);
      pairs.add(sorted.sublist(i, end));
    }
    return pairs;
  }

  void _syncAutoPage(int pageCount) {
    if (pageCount == _lastPairCount) return;
    _lastPairCount = pageCount;
    _autoPageTimer?.cancel();
    if (pageCount > 1 && !_userInteracting) _startAutoPage(pageCount);
  }

  void _startAutoPage(int pageCount) {
    _autoPageTimer?.cancel();
    _autoPageTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _userInteracting || !_pageController.hasClients) return;
      final next = (_pageIndex + 1) % pageCount;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
      );
    });
  }

  bool _onPageScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pauseAutoScroll();
    } else if (notification is ScrollEndNotification) {
      _scheduleAutoScrollResume();
    }
    return false;
  }

  void _pauseAutoScroll() {
    _userInteracting = true;
    _autoPageTimer?.cancel();
    _resumeTimer?.cancel();
  }

  void _scheduleAutoScrollResume() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _userInteracting = false);
      final pairs =
          _pairs(_sortedTracked(VitalsState.instance.tracked.toList()));
      if (pairs.length > 1) _startAutoPage(pairs.length);
    });
  }

  void _goToPage(int page, int pageCount) {
    if (!_pageController.hasClients || pageCount <= 1) return;
    _pauseAutoScroll();
    _pageController.animateToPage(
      page.clamp(0, pageCount - 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOut,
    );
    _scheduleAutoScrollResume();
  }

  void _prevPage(int pageCount) {
    final prev = _pageIndex == 0 ? pageCount - 1 : _pageIndex - 1;
    _goToPage(prev, pageCount);
  }

  void _nextPage(int pageCount) {
    _goToPage((_pageIndex + 1) % pageCount, pageCount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracked = VitalsState.instance.tracked.toList();
    final hasReading =
        tracked.any((v) => VitalsState.instance.latestOf(v) != null);
    final newest = _newestReadingAt(tracked);
    final pairs = _pairs(_sortedTracked(tracked));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncAutoPage(pairs.length);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Recent vitals',
          icon: AppIcons.vitals,
          actionLabel: 'See all',
          onAction: () =>
              Navigator.of(context).pushNamed(RouteNames.patientVitals),
        ),
        if (tracked.isEmpty)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.vitals,
              title: 'No vitals tracked',
              message: 'Choose vitals to monitor on the Vitals screen.',
              actionLabel: 'Open vitals',
              onAction: () =>
                  Navigator.of(context).pushNamed(RouteNames.patientVitals),
              compact: true,
            ),
          )
        else if (!hasReading)
          GlassCard(
            frosted: true,
            child: EmptyStateView(
              icon: AppIcons.vitals,
              title: 'No readings yet',
              message: 'Log your first vital to see it here.',
              actionLabel: 'Log vital',
              onAction: () => SubmitVitalSheet.show(context),
              compact: true,
            ),
          )
        else
          Stack(
            clipBehavior: Clip.none,
            children: [
              GlassCard(
                frosted: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      newest == null
                          ? 'No readings yet'
                          : 'Updated ${_relativeTime(newest)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: _pairHeight,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onPageScroll,
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: pairs.length,
                          onPageChanged: (i) =>
                              setState(() => _pageIndex = i),
                          itemBuilder: (_, pageIndex) {
                            final pair = pairs[pageIndex];
                            return Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: pairs.length > 1 ? 30 : 0,
                              ),
                              child: Column(
                                children: [
                                  _VitalDetailTile(
                                    vital: pair[0],
                                    reading: VitalsState.instance
                                        .latestOf(pair[0]),
                                  ),
                                  if (pair.length > 1) ...[
                                    const SizedBox(height: AppSpacing.xs),
                                    _VitalDetailTile(
                                      vital: pair[1],
                                      reading: VitalsState.instance
                                          .latestOf(pair[1]),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (pairs.length > 1) ...[
                Positioned(
                  left: -10,
                  bottom: AppSpacing.sm,
                  height: _pairHeight,
                  width: 46,
                  child: Center(
                    child: _VitalPairNavArrow(
                      icon: AppIcons.chevronLeft,
                      onPressed: () => _prevPage(pairs.length),
                    ),
                  ),
                ),
                Positioned(
                  right: -10,
                  bottom: AppSpacing.sm,
                  height: _pairHeight,
                  width: 46,
                  child: Center(
                    child: _VitalPairNavArrow(
                      icon: AppIcons.chevronRight,
                      onPressed: () => _nextPage(pairs.length),
                    ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _VitalPairNavArrow extends StatelessWidget {
  const _VitalPairNavArrow({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  static const _size = 46.0;

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.brandIndigo;

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          splashColor: accent.withOpacity(0.2),
          highlightColor: accent.withOpacity(0.1),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: _size,
                width: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppPalette.surface(context).withOpacity(0.88),
                  border: Border.all(
                    color: AppPalette.isDark(context)
                        ? AppColors.darkBorderStrong.withOpacity(0.65)
                        : Colors.white.withOpacity(0.65),
                    width: 1.5,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withOpacity(0.5),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(icon, size: 28, color: accent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VitalDetailTile extends StatelessWidget {
  const _VitalDetailTile({
    required this.vital,
    required this.reading,
  });

  final VitalKey vital;
  final VitalReading? reading;

  String _statusLine(RiskLevel risk, AppNotification? alert) {
    if (alert != null) return alert.title;
    return switch (risk) {
      RiskLevel.critical => 'Needs immediate attention',
      RiskLevel.warning => 'Outside your normal range',
      RiskLevel.normal => 'Within normal range',
      RiskLevel.unknown => 'No reading yet',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.accent;
    final risk = reading?.risk ?? RiskLevel.unknown;
    final value = reading?.formatValue() ?? 'â€”';
    final alert = NotificationState.instance.vitalAlertFor(vital);
    final when = reading == null
        ? 'Not logged'
        : _relativeTime(reading!.recordedAt);

    return Semantics(
      label:
          '${vital.label} $value ${vital.unit}, ${risk.label}. $when.',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => openVitalDetail(context, vital),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              // Neutral surface for every tile so the panel reads as one
              // consistent surface. Status is conveyed through the colored
              // border and the risk badge rather than a saturated fill.
              color: AppPalette.surfaceAlt(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(
                color: alert != null
                    ? alert.kind.tint.withOpacity(0.4)
                    : risk.color.withOpacity(
                        risk == RiskLevel.normal ? 0.22 : 0.30,
                      ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.14),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(vital.icon, color: accent, size: 17),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              vital.label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          RiskBadge(risk: risk, dense: true),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: value,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              ),
                            ),
                            TextSpan(
                              text: ' ${vital.unit}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppPalette.textMuted(context),
                                fontWeight: FontWeight.w500,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$when Â· ${_statusLine(risk, alert)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: alert != null
                              ? alert.kind.tint
                              : AppPalette.textMuted(context),
                          fontSize: 10,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (alert != null) ...[
                  const SizedBox(width: 4),
                  Icon(AppIcons.alert, size: 14, color: alert.kind.tint),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

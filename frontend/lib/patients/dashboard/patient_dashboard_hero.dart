part of 'patient_dashboard_view.dart';

class _HeroInsightCard extends StatefulWidget {
  const _HeroInsightCard({
    required this.doses,
    required this.appointments,
    required this.unreadNotifications,
  });

  final List<MedicationDose> doses;
  final List<Appointment> appointments;
  final int unreadNotifications;

  @override
  State<_HeroInsightCard> createState() => _HeroInsightCardState();
}

class _HeroInsightCardState extends State<_HeroInsightCard> {
  int _slideIndex = 0;
  int _toastIndex = 0;
  bool _toastVisible = true;
  Timer? _slideTimer;
  Timer? _toastTimer;

  static const _toastDuration = Duration(milliseconds: 3500);

  @override
  void initState() {
    super.initState();
    _slideTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final slides = _slides();
      if (slides.length <= 1) return;
      setState(() => _slideIndex = (_slideIndex + 1) % slides.length);
    });
    _scheduleToastCycle();
  }

  void _scheduleToastCycle() {
    _toastTimer?.cancel();
    final toasts = _toasts();
    if (toasts.isEmpty) {
      setState(() => _toastVisible = false);
      return;
    }
    setState(() => _toastVisible = true);
    _toastTimer = Timer(_toastDuration, () {
      if (!mounted) return;
      final items = _toasts();
      if (items.isEmpty) {
        setState(() => _toastVisible = false);
        return;
      }
      if (items.length <= 1) {
        setState(() => _toastVisible = false);
        return;
      }
      setState(() {
        _toastIndex = (_toastIndex + 1) % items.length;
      });
      _scheduleToastCycle();
    });
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HeroInsightCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unreadNotifications != widget.unreadNotifications ||
        oldWidget.doses.length != widget.doses.length ||
        oldWidget.appointments.length != widget.appointments.length) {
      _toastIndex = 0;
      _scheduleToastCycle();
    }
  }

  int _vitalsLoggedToday() {
    final now = DateTime.now();
    return VitalsState.instance.all
        .where((r) =>
            r.recordedAt.year == now.year &&
            r.recordedAt.month == now.month &&
            r.recordedAt.day == now.day)
        .length;
  }

  List<_InsightSlide> _slides() {
    final slides = <_InsightSlide>[];
    final taken =
        widget.doses.where((d) => d.status == DoseStatus.taken).length;
    final totalDoses = widget.doses.length;
    final pending =
        widget.doses.where((d) => d.status != DoseStatus.taken).length;
    final vitalsToday = _vitalsLoggedToday();

    for (final key in VitalsState.instance.tracked) {
      final reading = VitalsState.instance.latestOf(key);
      if (reading?.risk == RiskLevel.critical) {
        slides.add(_InsightSlide(
          headline: '${key.shortLabel} reading is critical',
          detail: '${reading!.formatValue()} ${key.unit}',
          caption:
              'Tap for details â€” your care team was alerted.',
          icon: AppIcons.alert,
          accent: AppColors.critical,
          iconBg: AppPalette.criticalSoft(context),
          vital: key,
        ));
      } else if (reading?.risk == RiskLevel.warning) {
        slides.add(_InsightSlide(
          headline: '${key.shortLabel} is outside your normal range',
          detail: 'Latest: ${reading!.formatValue()} ${key.unit}',
          caption: 'Tap to view details and log again if symptoms persist.',
          icon: AppIcons.vitals,
          accent: key.accent,
          iconBg: AppPalette.warningSoft(context),
          vital: key,
        ));
      }
    }

    final medLine = totalDoses == 0
        ? 'No doses scheduled today'
        : '$taken/$totalDoses medications taken';
    final statsLine = vitalsToday == 0
        ? medLine
        : '$vitalsToday vital${vitalsToday == 1 ? '' : 's'} logged Â· $medLine';

    String defaultHeadline;
    String? defaultCaption;
    if (totalDoses == 0 && vitalsToday == 0) {
      defaultHeadline = 'Welcome back â€” your health hub is ready';
      defaultCaption = 'Log vitals or check messages to get started.';
    } else if (taken >= totalDoses && vitalsToday > 0 && pending == 0) {
      defaultHeadline = 'You\'re on track today';
      defaultCaption = 'Great work keeping up with your care plan.';
    } else if (pending > 0) {
      defaultHeadline = 'A few items still need your attention';
      defaultCaption =
          '$pending dose${pending == 1 ? '' : 's'} and updates are waiting below.';
    } else {
      defaultHeadline = 'Good progress â€” keep it up';
      defaultCaption = 'Stay consistent with vitals and medications.';
    }

    slides.add(_InsightSlide(
      headline: defaultHeadline,
      detail: statsLine,
      caption: defaultCaption,
      icon: AppIcons.home,
      accent: AppColors.brandIndigo,
      iconBg: AppPalette.infoSoft(context),
    ));

    return slides;
  }

  List<_HeroToast> _toasts() {
    final toasts = <_HeroToast>[];
    final pending =
        widget.doses.where((d) => d.status != DoseStatus.taken).length;

    if (widget.unreadNotifications > 0) {
      toasts.add(_HeroToast(
        label:
            '${widget.unreadNotifications} alert${widget.unreadNotifications == 1 ? '' : 's'}',
        detail: 'Unread messages and care team updates',
        icon: AppIcons.bell,
        accent: AppColors.critical,
        route: RouteNames.patientNotifications,
      ));
    }
    if (pending > 0) {
      toasts.add(_HeroToast(
        label: '$pending dose${pending == 1 ? '' : 's'} due today',
        detail: 'Log doses to stay on your medication schedule',
        icon: AppIcons.medication,
        accent: AppColors.glucoseAmber,
        route: RouteNames.patientMedications,
      ));
    }
    if (widget.appointments.isNotEmpty) {
      final a = widget.appointments.first;
      final when = DateUtils.isSameDay(a.scheduledAt, DateTime.now())
          ? 'Today'
          : DateUtils.isSameDay(
                  a.scheduledAt, DateTime.now().add(const Duration(days: 1)))
              ? 'Tomorrow'
              : DateFormat.MMMd().format(a.scheduledAt);
      final time = DateFormat.jm().format(a.scheduledAt);
      toasts.add(_HeroToast(
        label: 'Visit $when',
        detail: '${a.doctorName} Â· $time Â· ${a.type.label}',
        icon: AppIcons.appointment,
        accent: AppColors.bpPurple,
        route: RouteNames.patientAppointmentDetail,
        routeArgs: a.id,
      ));
    }
    return toasts;
  }

  void _openSlide(BuildContext context, _InsightSlide slide) {
    if (slide.vital != null) {
      openVitalDetail(context, slide.vital!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides();
    final slide = slides[_slideIndex % slides.length];
    final toasts = _toasts();
    final toast = toasts.isEmpty
        ? null
        : toasts[_toastIndex % toasts.length];

    return GlassCard(
      frosted: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSwitcher(
          duration: AppMotion.page,
          switchInCurve: AppMotion.easeOut,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          child: slide.isTappable
              ? Material(
                  key: ValueKey(slide.headline),
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openSlide(context, slide),
                    borderRadius:
                        BorderRadius.circular(AppSpacing.radiusMd),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _InsightSlideBody(slide: slide),
                    ),
                  ),
                )
              : _InsightSlideBody(
                  key: ValueKey(slide.headline),
                  slide: slide,
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (toast != null && _toastVisible) ...[
          AnimatedSwitcher(
            duration: AppMotion.page,
            switchInCurve: AppMotion.easeOut,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _HeroUpdatePopup(
              key: ValueKey(toast.label),
              toast: toast,
              onTap: () {
                if (toast.routeArgs != null) {
                  Navigator.of(context).pushNamed(
                    toast.route,
                    arguments: toast.routeArgs,
                  );
                } else {
                  Navigator.of(context).pushNamed(toast.route);
                }
              },
              onDismiss: () => setState(() => _toastVisible = false),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        ],
      ),
    );
  }
}

class _InsightSlide {
  const _InsightSlide({
    required this.headline,
    this.detail = '',
    this.caption,
    required this.icon,
    this.accent = AppColors.brandIndigo,
    this.iconBg = AppColors.infoSoft,
    this.vital,
  });
  final String headline;
  final String detail;
  final String? caption;
  final IconData icon;
  final Color accent;
  final Color iconBg;
  final VitalKey? vital;

  bool get isTappable => vital != null;
}

class _InsightSlideBody extends StatelessWidget {
  const _InsightSlideBody({super.key, required this.slide});
  final _InsightSlide slide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: slide.iconBg,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(slide.icon, color: slide.accent, size: 20),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slide.headline,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppPalette.ink(context),
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                  ),
                  if (slide.detail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      slide.detail,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: slide.accent,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                  if (slide.caption != null && slide.caption!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      slide.caption!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppPalette.textMuted(context),
                            height: 1.35,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (slide.isTappable) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                AppIcons.chevronRight,
                size: 18,
                color: slide.accent.withOpacity(0.75),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _HeroToast {
  const _HeroToast({
    required this.label,
    required this.detail,
    required this.icon,
    required this.route,
    this.accent = AppColors.brandIndigo,
    this.routeArgs,
  });
  final String label;
  final String detail;
  final IconData icon;
  final Color accent;
  final String route;
  final Object? routeArgs;
}

class _HeroUpdatePopup extends StatelessWidget {
  const _HeroUpdatePopup({
    super.key,
    required this.toast,
    required this.onTap,
    required this.onDismiss,
  });

  final _HeroToast toast;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          boxShadow: [
            BoxShadow(
              color: toast.accent.withOpacity(0.16),
              blurRadius: 18,
              offset: const Offset(0, 8),
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.surface(context).withOpacity(0.82),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(
                    color: toast.accent.withOpacity(0.32),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: toast.accent.withOpacity(0.14),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        border: Border.all(
                          color: toast.accent.withOpacity(0.28),
                        ),
                      ),
                      child: Icon(toast.icon, size: 20, color: toast.accent),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            toast.label,
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  color: AppPalette.ink(context),
                                  fontWeight: FontWeight.w800,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            toast.detail,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppPalette.textMuted(context),
                                  height: 1.2,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: onDismiss,
                      icon: Icon(
                        AppIcons.close,
                        size: 18,
                        color: AppPalette.textFaint(context),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(AppIcons.chevronRight,
                        size: 18, color: toast.accent.withOpacity(0.7)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

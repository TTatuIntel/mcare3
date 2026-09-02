part of 'patient_dashboard_view.dart';

/// A tappable row inside a scene — the thing the scene is asking for.
class _SceneAction {
  const _SceneAction({
    required this.icon,
    required this.accent,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String detail;
  final VoidCallback onTap;
}

/// A counted fact the scene can show without asking for anything.
class _SceneStat {
  const _SceneStat(this.label, this.value);

  final String label;
  final String value;
}

/// One full card of the home hub.
///
/// The card *is* the scene: its title, accent, icon, body and actions all
/// change together, so the surface reads as "Medicine time" or "Next
/// appointment" rather than as a fixed panel with a changing row inside it.
///
/// A scene with no [actions] is informational — it renders no ink, no chevron
/// and no button role, so nothing looks tappable that is not. Every line is
/// derived from a store; the hub never invents adherence, risk or schedule.
class _HubScene {
  const _HubScene({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.priority,
    required this.at,
    this.body,
    this.stats = const [],
    this.actions = const [],
    this.footnote,
    this.urgent = false,
  });

  final String id;

  /// The headline. Changes with the scene — this is the dynamic title.
  final String title;

  /// The accent-coloured line under the title.
  final String subtitle;

  final IconData icon;
  final Color accent;

  /// Higher sorts first. Ties break on [at], newest first.
  final int priority;
  final DateTime at;

  /// One short paragraph of what this is about.
  final String? body;

  /// Counted facts, shown as chips.
  final List<_SceneStat> stats;

  /// At most two are drawn; the rest live on the screen the action opens.
  final List<_SceneAction> actions;

  /// A quiet closing line — status, provenance, a caveat.
  final String? footnote;

  /// Keeps the rotation from carrying this past unnoticed.
  final bool urgent;

  bool get isActionable => actions.isNotEmpty;
}

/// Builds every scene the patient home can honestly show right now, from the
/// stores the session seeds, and ranks them.
List<_HubScene> _buildHubScenes(
  BuildContext context, {
  required List<Appointment> appointments,
  required List<MedicationDose> doses,
  required int unreadNotifications,
}) {
  final now = DateTime.now();
  final scenes = <_HubScene>[];

  // Actions the plan scene draws on. Built first because the focused scenes
  // and the plan overview are two views of the same work.
  final planActions = <_SceneAction>[];

  // --- Emergency -------------------------------------------------------------
  final sos = SosState.instance.activeEvent;
  if (SosState.instance.hasActiveSos && sos != null) {
    scenes.add(
      _HubScene(
        id: 'sos_${sos.id}',
        title: 'Emergency active',
        subtitle: '${sos.kind.label} · ${_relativeTime(sos.triggeredAt)}',
        icon: AppIcons.sos,
        accent: AppColors.critical,
        priority: 100,
        at: sos.triggeredAt,
        body: sos.respondedBy == null
            ? 'Your emergency contacts and care team have been alerted.'
            : '${sos.respondedBy} is responding.',
        footnote: sos.locationLabel,
        urgent: true,
        actions: [
          _SceneAction(
            icon: AppIcons.sos,
            accent: AppColors.critical,
            title: 'Open emergency status',
            detail: 'See who is responding',
            onTap: () => Navigator.of(context).pushNamed(RouteNames.patientSos),
          ),
        ],
      ),
    );
  }

  // --- A vital out of range --------------------------------------------------
  VitalKey? riskVital;
  for (final vital in VitalsState.instance.tracked) {
    final risk = VitalsState.instance.latestOf(vital)?.risk;
    if (risk == RiskLevel.critical) {
      riskVital = vital;
      break;
    }
    if (risk == RiskLevel.warning) riskVital ??= vital;
  }
  if (riskVital != null) {
    final key = riskVital;
    final reading = VitalsState.instance.latestOf(key);

    // A reading stays out of range long after somebody has dealt with it. The
    // card used to be driven by the number alone, so a patient who had already
    // been phoned by their doctor kept staring at the same red alarm — the one
    // piece of the conversation the app never passed on was the answer. When
    // the care team has closed the alert and nothing new is open, this becomes
    // the outcome they wrote, in their name.
    final openAlert = NotificationState.instance.vitalAlertFor(key);
    final closed = openAlert == null
        ? NotificationState.instance.resolutionNoticeFor(key)
        : null;

    final critical = reading?.risk == RiskLevel.critical;
    final accent = closed != null
        ? AppColors.success
        : (critical ? AppColors.critical : AppColors.warning);
    final action = _SceneAction(
      icon: key.icon,
      accent: accent,
      title: 'Review ${key.label.toLowerCase()}',
      detail: reading == null
          ? 'Open your latest reading'
          : '${reading.formatValue()} ${key.unit} · ${reading.risk.label}',
      onTap: () => openVitalDetail(context, key),
    );
    planActions.add(action);
    scenes.add(
      _HubScene(
        id: 'alert_${key.name}',
        title: closed != null ? 'Reviewed by your care team' : 'Care alert',
        subtitle: closed != null
            ? '${key.label} · Handled'
            : '${key.label} · ${reading?.risk.label ?? 'Needs review'}',
        icon: key.icon,
        accent: accent,
        // A fresh answer outranks the plan for a day — the patient was just
        // alarmed by this reading and is owed the reply while they are still
        // wondering about it. After that it settles below the day's routine
        // rather than following them around.
        priority: closed != null
            ? (now.difference(closed.createdAt) < const Duration(days: 1)
                  ? 76
                  : 58)
            : (critical ? 96 : 88),
        at: closed?.createdAt ?? reading?.recordedAt ?? now,
        body: closed != null
            ? closed.body
            : (reading == null
                  ? 'This reading is outside your range.'
                  : '${reading.formatValue()} ${key.unit}, recorded ${_relativeTime(reading.recordedAt)}.'),
        footnote: closed != null && reading != null
            ? '${reading.formatValue()} ${key.unit}, recorded ${_relativeTime(reading.recordedAt)}.'
            : null,
        urgent: closed == null && critical,
        actions: [action],
      ),
    );
  }

  // --- Medication ------------------------------------------------------------
  final pending = doses.where((d) => d.status == DoseStatus.pending).toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  final takenToday = doses.where((d) => d.status == DoseStatus.taken).length;
  if (pending.isNotEmpty) {
    final next = pending.first;
    final overdue = next.scheduledAt.isBefore(now);
    final accent = overdue ? AppColors.warning : AppColors.success;
    final doseActions = [
      for (final dose in pending.take(2))
        _SceneAction(
          icon: AppIcons.medication,
          accent: dose.scheduledAt.isBefore(now)
              ? AppColors.warning
              : AppColors.success,
          title: 'Take ${dose.name}',
          detail:
              '${dose.dosage} · ${DateFormat.jm().format(dose.scheduledAt)}'
              '${dose.scheduledAt.isBefore(now) ? ' · past due' : ''}',
          onTap: () => LogDoseSheet.show(context, dose),
        ),
    ];
    planActions.add(doseActions.first);
    scenes.add(
      _HubScene(
        id: 'meds_${next.id}',
        title: 'Medicine time',
        subtitle: overdue
            ? '${next.name} · past due'
            : '${next.name} · ${DateFormat.jm().format(next.scheduledAt)}',
        icon: AppIcons.medication,
        accent: accent,
        priority: overdue ? 92 : 78,
        at: next.scheduledAt,
        body: next.instructions,
        stats: [
          _SceneStat('Due', '${pending.length}'),
          if (takenToday > 0) _SceneStat('Taken', '$takenToday'),
        ],
        urgent: overdue,
        actions: doseActions,
      ),
    );
  }

  // --- Appointments ----------------------------------------------------------
  if (appointments.isNotEmpty) {
    final appt = appointments.first;
    final today = DateUtils.isSameDay(appt.scheduledAt, now);
    final action = _SceneAction(
      icon: AppIcons.appointment,
      accent: AppColors.bpPurple,
      title: today ? 'Open today\'s visit' : 'View appointment',
      detail: _patientVisitTime(appt.scheduledAt),
      onTap: () => Navigator.of(
        context,
      ).pushNamed(RouteNames.patientAppointmentDetail, arguments: appt.id),
    );
    planActions.add(action);
    scenes.add(
      _HubScene(
        id: 'appt_${appt.id}',
        title: today ? 'Appointment today' : 'Next appointment',
        subtitle: _patientVisitTime(appt.scheduledAt),
        icon: appt.type.icon,
        accent: AppColors.bpPurple,
        priority: today ? 84 : 58,
        at: appt.scheduledAt,
        body: [
          appt.doctorName,
          if (appt.doctorSpecialty.isNotEmpty) appt.doctorSpecialty,
          appt.type.label,
        ].join(' · '),
        stats: [
          _SceneStat('Status', appt.status.label),
          _SceneStat('Length', '${appt.durationMinutes} min'),
        ],
        footnote: appt.reason,
        actions: [action],
      ),
    );
  }

  // --- Messages --------------------------------------------------------------
  final unreadThreads = MessagesState.instance.conversations
      .where((c) => c.unreadCount > 0)
      .toList();
  if (unreadThreads.isNotEmpty) {
    final convo = unreadThreads.first;
    final total = unreadThreads.fold<int>(0, (sum, c) => sum + c.unreadCount);
    scenes.add(
      _HubScene(
        id: 'msg_${convo.id}',
        title: unreadThreads.length == 1 ? 'New message' : 'New messages',
        subtitle: unreadThreads.length == 1
            ? '${convo.participant.name} · ${_relativeTime(convo.lastMessage.sentAt)}'
            : '$total unread across ${unreadThreads.length} conversations',
        icon: AppIcons.chat,
        accent: AppColors.info,
        priority: 80,
        at: convo.lastMessage.sentAt,
        body: convo.lastMessage.body,
        actions: [
          for (final c in unreadThreads.take(2))
            _SceneAction(
              icon: AppIcons.chat,
              accent: AppColors.info,
              title: c.participant.name,
              detail:
                  '${c.unreadCount} unread · ${_relativeTime(c.lastMessage.sentAt)}',
              onTap: () => Navigator.of(
                context,
              ).pushNamed(RouteNames.patientChatThread, arguments: c.id),
            ),
        ],
      ),
    );
  }

  // --- Announcements ---------------------------------------------------------
  for (final ann in AnnouncementsState.instance.live.take(2)) {
    final fresh = now.difference(ann.effectiveAt).inHours < 24;
    scenes.add(
      _HubScene(
        id: 'ann_${ann.id}',
        title: 'Announcement',
        subtitle: [
          if ((ann.createdBy ?? '').isNotEmpty) ann.createdBy!,
          _relativeTime(ann.effectiveAt),
        ].join(' · '),
        icon: AppIcons.announcements,
        accent: AppColors.adminPurple,
        priority: fresh ? 72 : 64,
        at: ann.effectiveAt,
        body: ann.title,
        actions: [
          _SceneAction(
            icon: AppIcons.announcements,
            accent: AppColors.adminPurple,
            title: 'Read announcement',
            detail: ann.hasLink ? 'Includes a link' : 'Open the full notice',
            onTap: () => _AnnouncementSheet.show(context, ann),
          ),
        ],
      ),
    );
  }

  // --- Documents and uploads -------------------------------------------------
  // Home only calls out the newest recent file. The Documents screen remains
  // the complete record while this scene answers "what just changed?".
  final documents = DocumentsState.instance.all;
  if (documents.isNotEmpty) {
    final document = documents.first;
    final age = now.difference(document.uploadedAt);
    if (!age.isNegative && age <= const Duration(days: 14)) {
      final fromCareTeam = document.source != DocumentSource.patient;
      scenes.add(
        _HubScene(
          id: 'document_${document.id}',
          title: fromCareTeam ? 'New document' : 'Document uploaded',
          subtitle:
              '${document.category.label} · ${_relativeTime(document.uploadedAt)}',
          icon: document.category.icon,
          accent: document.category.color,
          priority: fromCareTeam ? 68 : 52,
          at: document.uploadedAt,
          body: document.title,
          actions: [
            _SceneAction(
              icon: AppIcons.document,
              accent: document.category.color,
              title: 'Open documents',
              detail: document.title,
              onTap: () =>
                  Navigator.of(context).pushNamed(RouteNames.patientDocuments),
            ),
          ],
        ),
      );
    }
  }

  // --- Assigned meals --------------------------------------------------------
  final mealsToday = MealPlansState.instance.assignedToday;
  final meal = mealsToday.isNotEmpty
      ? mealsToday.first
      : MealPlansState.instance.latest;
  final mealIsToday = mealsToday.isNotEmpty;
  if (meal != null &&
      (mealIsToday || now.difference(meal.assignedAt).inDays <= 7)) {
    scenes.add(
      _HubScene(
        id: 'meal_${meal.id}',
        title: mealsToday.length > 1 ? 'Assigned meals' : 'Assigned meal',
        subtitle: mealsToday.length > 1
            ? '${mealsToday.length} for today'
            : '${meal.mealType.label} · ${mealIsToday ? 'today' : 'assigned ${_relativeTime(meal.assignedAt)}'}',
        icon: meal.mealType.icon,
        accent: meal.mealType.color,
        priority: mealIsToday ? 62 : 48,
        at: meal.assignedAt,
        body: (meal.description ?? '').isNotEmpty
            ? '${meal.title} — ${meal.description}'
            : meal.title,
        stats: [
          if (meal.calories != null) _SceneStat('Calories', '${meal.calories}'),
          if (meal.protein != null) _SceneStat('Protein', meal.protein!),
          if (meal.carbs != null) _SceneStat('Carbs', meal.carbs!),
        ],
        footnote: meal.assignedBy.isEmpty
            ? null
            : 'Assigned by ${meal.assignedBy}',
        actions: [
          for (final m in (mealIsToday ? mealsToday : [meal]).take(2))
            _SceneAction(
              icon: m.mealType.icon,
              accent: m.mealType.color,
              title: m.title,
              detail: [
                m.mealType.label,
                if (m.macroSummary.isNotEmpty) m.macroSummary,
              ].join(' · '),
              onTap: () => _MealPlanSheet.show(context, m),
            ),
        ],
      ),
    );
  }

  // --- Vitals: the step, and the tally --------------------------------------
  final tracked = VitalsState.instance.tracked.toList();
  final loggedToday = tracked
      .where(
        (k) => DateUtils.isSameDay(
          VitalsState.instance.latestOf(k)?.recordedAt,
          now,
        ),
      )
      .length;
  final allLogged = tracked.isNotEmpty && loggedToday == tracked.length;
  planActions.add(
    _SceneAction(
      icon: AppIcons.vitals,
      accent: AppColors.brandIndigo,
      title: 'Record your vitals',
      detail: tracked.isEmpty
          ? 'Choose a vital and add today\'s reading'
          : allLogged
          ? 'Add another reading any time'
          : 'Keep your care team up to date',
      onTap: () => SubmitVitalSheet.show(
        context,
        initial: tracked.isEmpty ? null : tracked.first,
      ),
    ),
  );

  // --- Notification centre ---------------------------------------------------
  if (unreadNotifications > 0) {
    final action = _SceneAction(
      icon: AppIcons.bell,
      accent: AppColors.brandIndigo,
      title: 'Review care updates',
      detail:
          '$unreadNotifications unread update${unreadNotifications == 1 ? '' : 's'}',
      onTap: () =>
          Navigator.of(context).pushNamed(RouteNames.patientNotifications),
    );
    planActions.add(action);
    scenes.add(
      _HubScene(
        id: 'updates',
        title: 'Care updates',
        subtitle:
            '$unreadNotifications unread update${unreadNotifications == 1 ? '' : 's'}',
        icon: AppIcons.bell,
        accent: AppColors.brandIndigo,
        priority: 55,
        at: now,
        body: 'Alerts, results and notes from your care team collect here.',
        actions: [action],
      ),
    );
  }

  // --- Support ---------------------------------------------------------------
  for (final ticket in SupportState.instance.open) {
    final lastReply = ticket.replies.isEmpty ? null : ticket.replies.last;
    if (lastReply == null || !lastReply.isStaff) continue;
    scenes.add(
      _HubScene(
        id: 'ticket_${ticket.id}',
        title: 'Support replied',
        subtitle: '${lastReply.author} · ${_relativeTime(lastReply.sentAt)}',
        icon: AppIcons.support,
        accent: AppColors.info,
        priority: 60,
        at: lastReply.sentAt,
        body: lastReply.body,
        footnote: ticket.subject,
        actions: [
          _SceneAction(
            icon: AppIcons.ticket,
            accent: AppColors.info,
            title: 'Open your ticket',
            detail: ticket.subject,
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.patientSupport),
          ),
        ],
      ),
    );
    break;
  }

  // --- A report request already sent (status only, nothing to tap) ----------
  final pendingReports = VitalReportState.instance.pending;
  if (pendingReports.isNotEmpty) {
    final request = pendingReports.first;
    scenes.add(
      _HubScene(
        id: 'report_${request.id}',
        title: 'Report request',
        subtitle: 'Sent ${_relativeTime(request.createdAt)} · awaiting reply',
        icon: AppIcons.report,
        accent: AppColors.doctorGreen,
        priority: 50,
        at: request.createdAt,
        body:
            'Your care team has your request. You will be notified here when '
            'they respond.',
        stats: [
          _SceneStat('Open', '${pendingReports.length}'),
          _SceneStat('Vitals', '${request.vitals.length}'),
        ],
      ),
    );
  }

  // --- Profile ---------------------------------------------------------------
  final completion = ProfileCompletion.forUser(
    user: AuthState.instance.user,
    health: ProfileState.instance.health,
    contacts: ProfileState.instance.emergencyContacts,
    assignedVitals: VitalsState.instance.assigned.toList(),
  );
  if (!completion.isComplete && completion.incompleteItems.isNotEmpty) {
    scenes.add(
      _HubScene(
        id: 'profile',
        title: 'Finish your profile',
        subtitle: '${completion.percent}% complete',
        icon: AppIcons.user,
        accent: AppColors.brandIndigo,
        priority: 42,
        at: now,
        body:
            'Next: ${completion.incompleteItems.first.label}. A complete '
            'profile means your care team is not guessing.',
        actions: [
          _SceneAction(
            icon: AppIcons.user,
            accent: AppColors.brandIndigo,
            title: 'Complete your profile',
            detail: completion.incompleteItems.first.label,
            onTap: () =>
                Navigator.of(context).pushNamed(RouteNames.patientProfile),
          ),
        ],
      ),
    );
  }

  // --- Today's tally (counted, never judged) --------------------------------
  if (tracked.isNotEmpty || doses.isNotEmpty) {
    scenes.add(
      _HubScene(
        id: 'progress',
        title: 'Today\'s progress',
        subtitle: tracked.isEmpty
            ? '$takenToday of ${doses.length} doses taken'
            : '$loggedToday of ${tracked.length} tracked vitals logged',
        icon: allLogged ? AppIcons.check : AppIcons.trend,
        accent: allLogged ? AppColors.success : AppColors.weightSlate,
        priority: allLogged ? 44 : 30,
        at: now,
        body: allLogged
            ? 'Every tracked vital is logged — your care team has today\'s '
                  'full picture.'
            : 'Counted from what you have saved since midnight.',
        stats: [
          if (tracked.isNotEmpty)
            _SceneStat('Vitals', '$loggedToday/${tracked.length}'),
          if (doses.isNotEmpty)
            _SceneStat('Doses', '$takenToday/${doses.length}'),
          if (appointments.isNotEmpty)
            _SceneStat(
              'Next visit',
              _patientVisitTime(appointments.first.scheduledAt),
            ),
        ],
      ),
    );
  }

  // --- The plan: the overview the focused scenes come from ------------------
  final planSteps = planActions.length;
  scenes.add(
    _HubScene(
      id: 'plan',
      title: 'Your plan today',
      subtitle: '$planSteps priority step${planSteps == 1 ? '' : 's'}',
      icon: AppIcons.catalog,
      accent: AppColors.brandIndigo,
      priority: 74,
      at: now,
      actions: planActions.take(2).toList(),
      footnote: planSteps > 2
          ? '+${planSteps - 2} more in the cards that follow'
          : null,
    ),
  );

  // --- Welcome: the calm one, and the last turn -----------------------------
  final firstName = AuthState.instance.user?.firstName ?? '';
  final urgentCount = scenes.where((s) => s.urgent).length;
  scenes.add(
    _HubScene(
      id: 'welcome',
      title: firstName.isEmpty ? 'Welcome back' : 'Welcome back, $firstName',
      subtitle: DateFormat.yMMMMEEEEd().format(now),
      icon: AppIcons.home,
      accent: AppColors.brandIndigo,
      priority: 20,
      at: now,
      body: urgentCount > 0
          ? 'Something needs you today — the cards above show what.'
          : 'Nothing is overdue right now. Swipe through today, or log a '
                'reading whenever you are ready.',
      stats: [
        if (tracked.isNotEmpty)
          _SceneStat('Vitals logged', '$loggedToday/${tracked.length}'),
        if (pending.isNotEmpty) _SceneStat('Doses due', '${pending.length}'),
        if (appointments.isNotEmpty)
          _SceneStat(
            'Next visit',
            _patientVisitTime(appointments.first.scheduledAt),
          ),
      ],
    ),
  );

  scenes.sort((a, b) {
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    return b.at.compareTo(a.at);
  });
  return scenes;
}

/// The home hub: one card that becomes each thing today holds in turn —
/// "Your plan today", "Medicine time", "Next appointment", "Assigned meal",
/// "Announcement", "Welcome back". Title, accent, body and actions change
/// together, so the whole card is the live surface, not a strip inside it.
class _PatientTodayHub extends StatefulWidget {
  const _PatientTodayHub({
    required this.appointments,
    required this.doses,
    required this.unreadNotifications,
  });

  final List<Appointment> appointments;
  final List<MedicationDose> doses;
  final int unreadNotifications;

  @override
  State<_PatientTodayHub> createState() => _PatientTodayHubState();
}

class _PatientTodayHubState extends State<_PatientTodayHub>
    with TickerProviderStateMixin {
  /// How long each scene holds the card. Long enough to read a title and two
  /// lines, short enough that the last of eight is seen inside a minute.
  static const _dwell = Duration(seconds: 6);

  /// How long the card stays put after the patient swipes it themselves.
  static const _resumeAfter = Duration(seconds: 15);

  static const _maxScenes = 8;

  late final AnimationController _pulse;
  late final AnimationController _flash;

  Timer? _rotationTimer;
  Timer? _resumeTimer;
  int _index = 0;
  int _sceneCount = 0;
  String _signature = '';

  /// Read from [MediaQuery] each build — the same source the staff urgent
  /// strip uses — so a platform setting and a test override both land.
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: AppMotion.pulseCycle);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    _resumeTimer?.cancel();
    _pulse.dispose();
    _flash.dispose();
    super.dispose();
  }

  /// Keeps the timer, the page index and the "new content" flash in step with
  /// whatever the stores now hold.
  void _syncRotation(List<_HubScene> scenes) {
    final signature = scenes.map((s) => s.id).join('|');
    final changed = signature != _signature;
    _signature = signature;
    _sceneCount = scenes.length;

    if (changed) {
      if (_index >= scenes.length) _index = 0;
      if (!_reduceMotion && scenes.isNotEmpty) {
        _flash
          ..reset()
          ..forward();
      }
      _restartTimer();
    }

    final urgent = scenes.any((s) => s.urgent);
    if (urgent && !_reduceMotion) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  void _restartTimer() {
    _rotationTimer?.cancel();
    if (_reduceMotion || _sceneCount < 2) return;
    _rotationTimer = Timer.periodic(_dwell, (_) => _advance());
  }

  void _advance() => _goTo(_index + 1);

  void _goTo(int index) {
    if (!mounted || _sceneCount < 1) return;
    setState(() => _index = (index + _sceneCount) % _sceneCount);
  }

  /// A swipe means the patient is reading — hold this scene, then resume.
  void _onUserSwipe() {
    _rotationTimer?.cancel();
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_resumeAfter, () {
      if (mounted) _restartTimer();
    });
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
        _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

        final scenes = _buildHubScenes(
          context,
          appointments: widget.appointments,
          doses: widget.doses,
          unreadNotifications: widget.unreadNotifications,
        ).take(_maxScenes).toList();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncRotation(scenes);
        });

        final current = scenes[_index.clamp(0, scenes.length - 1)];

        // The card takes the scene's colour with it: the whole surface
        // changes, not a row inside it.
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: current.accent),
          duration: _reduceMotion ? Duration.zero : AppMotion.page,
          curve: AppMotion.easeOut,
          builder: (context, accent, _) {
            final tint = accent ?? current.accent;
            return AnimatedBuilder(
              animation: Listenable.merge([_pulse, _flash]),
              builder: (context, child) {
                // One ring, two jobs: a slow pulse while something urgent is
                // in the rotation, and a single flash when new content lands.
                final glow = current.urgent
                    ? 0.16 + 0.30 * _pulse.value
                    : 0.34 * (1 - Curves.easeOut.transform(_flash.value));
                return GlassCard(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      tint.withValues(alpha: 0.12),
                      AppPalette.surface(context),
                    ],
                  ),
                  border: Border.all(
                    color: tint.withValues(alpha: current.urgent ? 0.42 : 0.20),
                    width: current.urgent ? 1.4 : 1,
                  ),
                  shadow: glow <= 0.01
                      ? null
                      : [
                          BoxShadow(
                            color: tint.withValues(alpha: glow),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ],
                  child: child!,
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SceneDeck(
                    scenes: scenes,
                    index: _index.clamp(0, scenes.length - 1),
                    animate: !_reduceMotion,
                    onSwipe: (forward) {
                      _onUserSwipe();
                      _goTo(_index + (forward ? 1 : -1));
                    },
                  ),
                  if (scenes.length > 1) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _HubFooter(
                      count: scenes.length,
                      index: _index.clamp(0, scenes.length - 1),
                      accent: tint,
                      live: !_reduceMotion,
                      onSelect: (i) {
                        _onUserSwipe();
                        _goTo(i);
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The current scene only. Its height is content-driven, so a short
/// announcement no longer inherits the empty space required by a taller
/// two-action scene. [AnimatedSize] keeps the rest of the page from snapping
/// when the live surface changes.
class _SceneDeck extends StatelessWidget {
  const _SceneDeck({
    required this.scenes,
    required this.index,
    required this.animate,
    required this.onSwipe,
  });

  final List<_HubScene> scenes;
  final int index;
  final bool animate;

  /// True for the next scene, false for the previous one.
  final ValueChanged<bool> onSwipe;

  @override
  Widget build(BuildContext context) {
    final current = KeyedSubtree(
      key: ValueKey(scenes[index].id),
      child: _HubSceneView(scene: scenes[index]),
    );

    return GestureDetector(
      // Horizontal only: the page under this card scrolls vertically, and a
      // tap still reaches the action rows.
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity.abs() < 120 || scenes.length < 2) return;
        onSwipe(velocity < 0);
      },
      child: animate
          ? AnimatedSize(
              duration: AppMotion.page,
              curve: AppMotion.easeOut,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: AppMotion.page,
                switchInCurve: AppMotion.easeOut,
                layoutBuilder: (currentChild, _) =>
                    currentChild ?? const SizedBox.shrink(),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: current,
              ),
            )
          : current,
    );
  }
}

/// With animations off nothing may hide behind a timer: the leading scene is
/// drawn in full and the rest are listed under it, still reachable.
class _StaticHubCard extends StatelessWidget {
  const _StaticHubCard({required this.scenes});

  final List<_HubScene> scenes;

  @override
  Widget build(BuildContext context) {
    final lead = scenes.first;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          lead.accent.withValues(alpha: 0.12),
          AppPalette.surface(context),
        ],
      ),
      border: Border.all(color: lead.accent.withValues(alpha: 0.20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HubSceneView(scene: lead),
          for (final scene in scenes.skip(1)) ...[
            const SizedBox(height: AppSpacing.sm),
            _HubSceneSummaryRow(scene: scene),
          ],
        ],
      ),
    );
  }
}

/// One scene, drawn as the whole card: title, accent line, body, facts and
/// the actions it is asking for.
class _HubSceneView extends StatelessWidget {
  const _HubSceneView({required this.scene});

  final _HubScene scene;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The deck is as tall as its tallest scene, so a scene that showed
    // everything it holds would stretch every other one. Two shapes keep the
    // card comparable turn to turn, and the ask always wins:
    //   two actions            → header + the two rows;
    //   one action or none     → header + body + facts + the row.
    // The footnote is the first thing dropped when the scene is already
    // carrying both a paragraph and a row of facts.
    final twoActions = scene.actions.length >= 2;
    final showBody = scene.body != null && !twoActions;
    final showStats = scene.stats.isNotEmpty && !twoActions;
    final showFootnote =
        scene.footnote != null && !twoActions && !(showBody && showStats);

    final children = <Widget>[
      Row(
        children: [
          _PatientIconDisc(icon: scene.icon, color: scene.accent, size: 46),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scene.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  scene.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scene.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (showBody) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          scene.body!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppPalette.textMuted(context),
            height: 1.35,
          ),
        ),
      ],
      if (showStats) ...[
        const SizedBox(height: AppSpacing.sm),
        _SceneStatsRow(stats: scene.stats, accent: scene.accent),
      ],
      for (var i = 0; i < scene.actions.length && i < 2; i++) ...[
        const SizedBox(height: AppSpacing.sm),
        _SceneActionRow(action: scene.actions[i]),
      ],
      if (showFootnote) ...[
        const SizedBox(height: AppSpacing.sm),
        Text(
          scene.footnote!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppPalette.textFaint(context),
          ),
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// The scenes below the leading one when the card is not rotating.
class _HubSceneSummaryRow extends StatelessWidget {
  const _HubSceneSummaryRow({required this.scene});

  final _HubScene scene;

  @override
  Widget build(BuildContext context) {
    final action = scene.actions.isEmpty ? null : scene.actions.first;
    return _SceneActionRow(
      action: _SceneAction(
        icon: scene.icon,
        accent: scene.accent,
        title: scene.title,
        detail: scene.subtitle,
        onTap: action?.onTap ?? () {},
      ),
      informational: action == null,
    );
  }
}

/// A row the scene is asking the patient to act on. With [informational] it
/// carries no ink, no chevron and no button role.
class _SceneActionRow extends StatelessWidget {
  const _SceneActionRow({required this.action, this.informational = false});

  final _SceneAction action;
  final bool informational;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppSpacing.radiusLg);

    final body = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: radius,
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          _PatientIconDisc(icon: action.icon, color: action.accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  action.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
              ],
            ),
          ),
          if (!informational) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(AppIcons.chevronRight, color: action.accent),
          ],
        ],
      ),
    );

    final label = '${action.title}. ${action.detail}';

    if (informational) {
      return Semantics(
        label: label,
        readOnly: true,
        excludeSemantics: true,
        child: body,
      );
    }

    // `onTap` is declared on this node, not only on the ink below it: the
    // descendants are excluded, so a screen reader's activation has to have
    // somewhere to land.
    return Semantics(
      button: true,
      label: label,
      onTap: action.onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(onTap: action.onTap, borderRadius: radius, child: body),
      ),
    );
  }
}

class _SceneStatsRow extends StatelessWidget {
  const _SceneStatsRow({required this.stats, required this.accent});

  final List<_SceneStat> stats;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final stat in stats.take(3))
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              '${stat.label} ${stat.value}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

/// Position dots on the left of the card's foot, with the live badge on the
/// right — the card says both where you are and that it is moving.
class _HubFooter extends StatelessWidget {
  const _HubFooter({
    required this.count,
    required this.index,
    required this.accent,
    required this.live,
    required this.onSelect,
  });

  final int count;
  final int index;
  final Color accent;
  final bool live;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              for (var i = 0; i < count; i++)
                Semantics(
                  label: 'Card ${i + 1} of $count',
                  selected: i == index,
                  button: true,
                  child: InkResponse(
                    onTap: () => onSelect(i),
                    radius: 14,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: AppSpacing.xs,
                      ),
                      child: AnimatedContainer(
                        duration: AppMotion.micro,
                        height: 6,
                        width: i == index ? 18 : 6,
                        decoration: BoxDecoration(
                          color: i == index
                              ? accent
                              : AppPalette.borderStrong(context),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (live)
          _HubLivePill(accent: accent)
        else
          _HubPausedPill(accent: accent),
      ],
    );
  }
}

class _HubPausedPill extends StatelessWidget {
  const _HubPausedPill({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        'Swipe',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Tells the patient the card moves on its own.
class _HubLivePill extends StatefulWidget {
  const _HubLivePill({required this.accent});

  final Color accent;

  @override
  State<_HubLivePill> createState() => _HubLivePillState();
}

class _HubLivePillState extends State<_HubLivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppMotion.pulseCycle,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: widget.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1).animate(_ctrl),
            child: Container(
              height: 7,
              width: 7,
              decoration: BoxDecoration(
                color: widget.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: widget.accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full announcement text, plus its link when the admin attached one.
class _AnnouncementSheet {
  _AnnouncementSheet._();

  static Future<void> show(BuildContext context, AppAnnouncement ann) {
    return PatientSheet.show<void>(
      context,
      title: ann.title,
      subtitle: [
        if ((ann.createdBy ?? '').isNotEmpty) ann.createdBy!,
        _relativeTime(ann.effectiveAt),
      ].join(' · '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ann.body,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          if (ann.endsAt != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Shown until ${DateFormat.yMMMd().add_jm().format(ann.endsAt!)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ],
          if (ann.hasLink) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: (ann.ctaLabel ?? '').trim().isNotEmpty
                  ? ann.ctaLabel!
                  : 'Open link',
              icon: AppIcons.link,
              expand: true,
              onPressed: () async {
                final opened = await GoogleMapsService.openUrl(ann.ctaUrl!);
                if (!opened && context.mounted) {
                  AppToast.error(context, 'Could not open that link.');
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// The assigned meal in full — what it is, the macros the clinician set, and
/// any note attached to it.
class _MealPlanSheet {
  _MealPlanSheet._();

  static Future<void> show(BuildContext context, StaffMealPlan meal) {
    final theme = Theme.of(context);
    return PatientSheet.show<void>(
      context,
      title: meal.title,
      subtitle:
          '${meal.mealType.label} · assigned ${_relativeTime(meal.assignedAt)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((meal.description ?? '').isNotEmpty)
            Text(
              meal.description!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          const SizedBox(height: AppSpacing.md),
          if (meal.macroSummary.isNotEmpty)
            PatientCompactInfoRow(label: 'Nutrition', value: meal.macroSummary),
          if ((meal.notes ?? '').isNotEmpty)
            PatientCompactInfoRow(label: 'Care team note', value: meal.notes!),
          if (meal.assignedBy.isNotEmpty)
            PatientCompactInfoRow(label: 'Assigned by', value: meal.assignedBy),
        ],
      ),
    );
  }
}

part of 'patient_dashboard_view.dart';

/// A tappable row inside a scene — the thing the scene is asking for.
class _SceneAction {
  const _SceneAction({
    required this.icon,
    required this.accent,
    required this.title,
    required this.detail,
    required this.onTap,
    this.standing = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String detail;
  final VoidCallback onTap;

  /// A standing offer rather than something today is waiting on — "add another
  /// reading any time". It stays on the page as a row, but it is not counted
  /// in the headline: a day with nothing outstanding must be allowed to say
  /// so.
  final bool standing;
}

/// A counted fact the scene can show without asking for anything.
class _SceneStat {
  const _SceneStat(this.label, this.value);

  final String label;
  final String value;
}

/// One thing today holds: an alert, a due dose, a visit, a notice, a tally.
///
/// A scene names itself — "Medicine time", "Next appointment" — and carries
/// the lines that belong to it. The page lists scenes; it no longer turns
/// through them.
///
/// A scene with no [actions] is informational — it renders no ink, no chevron
/// and no button role, so nothing looks tappable that is not. Every line is
/// derived from a store; the page never invents adherence, risk or schedule.
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

  /// The first is the row's destination; the rest live on the screen it opens.
  final List<_SceneAction> actions;

  /// A quiet closing line — status, provenance, a caveat.
  final String? footnote;

  /// Something is wrong now: it leads the stream and the briefing says so.
  final bool urgent;

  bool get isActionable => actions.isNotEmpty;
}

/// A counted fact about today, written as one tappable phrase on the page
/// background: "Vitals 2/4". No chip, no tile — the number is the whole
/// widget, and tapping it opens the screen the number came from.
class _HubFact {
  const _HubFact({
    required this.label,
    required this.value,
    required this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final Color accent;
  final VoidCallback? onTap;
}

/// Everything the patient home knows about today, in the three shapes the
/// page uses it in: the ranked [scenes] the "For you" stream lists, the
/// [steps] that are actually asking the patient for something, and the
/// counted [facts] that only report.
class _HubBriefing {
  const _HubBriefing({
    required this.scenes,
    required this.steps,
    required this.facts,
  });

  final List<_HubScene> scenes;
  final List<_SceneAction> steps;
  final List<_HubFact> facts;

  int get urgentCount => scenes.where((s) => s.urgent).length;

  /// The steps today is actually waiting on — what the headline counts.
  int get outstandingCount => steps.where((s) => !s.standing).length;
}

/// Builds everything the patient home can honestly show right now, from the
/// stores the session seeds, and ranks it.
_HubBriefing _buildHubBriefing(
  BuildContext context, {
  required List<Appointment> appointments,
  required List<MedicationDose> doses,
  required int unreadNotifications,
}) {
  final now = DateTime.now();
  final scenes = <_HubScene>[];

  // The day's steps: the things that are actually asking the patient for
  // something. Built alongside the scenes because the two are views of the
  // same work — the briefing lists the steps, the feed lists the scenes.
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
              onTap: () => MealDetailSheet.show(context, m),
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
      standing: allLogged,
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

  scenes.sort((a, b) {
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    return b.at.compareTo(a.at);
  });

  final nextVisit = appointments.isEmpty ? null : appointments.first;

  return _HubBriefing(
    scenes: scenes,
    steps: planActions,
    facts: [
      if (tracked.isNotEmpty)
        _HubFact(
          label: 'Vitals',
          value: '$loggedToday/${tracked.length}',
          accent: allLogged ? AppColors.success : AppColors.brandIndigo,
          onTap: () =>
              Navigator.of(context).pushNamed(RouteNames.patientVitals),
        ),
      if (doses.isNotEmpty)
        _HubFact(
          label: 'Doses',
          value: '$takenToday/${doses.length}',
          accent: pending.isEmpty ? AppColors.success : AppColors.warning,
          onTap: () =>
              Navigator.of(context).pushNamed(RouteNames.patientMedications),
        ),
      if (nextVisit != null)
        _HubFact(
          label: 'Next visit',
          value: _patientVisitTime(nextVisit.scheduledAt),
          accent: AppColors.bpPurple,
          onTap: () => Navigator.of(context).pushNamed(
            RouteNames.patientAppointmentDetail,
            arguments: nextVisit.id,
          ),
        ),
    ],
  );
}

/// The ranked stream on its own — what the "For you" list is built from.
List<_HubScene> _buildHubScenes(
  BuildContext context, {
  required List<Appointment> appointments,
  required List<MedicationDose> doses,
  required int unreadNotifications,
}) => _buildHubBriefing(
  context,
  appointments: appointments,
  doses: doses,
  unreadNotifications: unreadNotifications,
).scenes;

/// The top of the patient home, written straight onto the page background.
///
/// This used to be a card that re-dealt itself every six seconds. Its height,
/// its colour and its whole contents changed under the reader: the page moved
/// while it was being used, and anything worth reading was gone before it was
/// read. Nothing here moves on its own and nothing is boxed.
///
/// What is left is the day in three parts, all of it on screen at once and all
/// of it tappable: one headline of what today is asking, the counted facts
/// underneath it, and the steps themselves as plain rows. The full stream is
/// the "For you" list further down; this is only its head.
class _PatientTodayHub extends StatelessWidget {
  const _PatientTodayHub({
    required this.appointments,
    required this.doses,
    required this.unreadNotifications,
  });

  final List<Appointment> appointments;
  final List<MedicationDose> doses;
  final int unreadNotifications;

  /// Steps drawn here. The rest are not hidden — they are rows in "For you".
  static const _maxSteps = 3;

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
        final briefing = _buildHubBriefing(
          context,
          appointments: appointments,
          doses: doses,
          unreadNotifications: unreadNotifications,
        );

        final theme = Theme.of(context);
        final steps = briefing.steps;
        final urgent = briefing.urgentCount;
        final outstanding = briefing.outstandingCount;
        final shown = steps.take(_maxSteps).toList();

        final headline = outstanding == 0
            ? 'Nothing needs you right now'
            : '$outstanding step${outstanding == 1 ? '' : 's'} today';
        final detail = urgent > 0
            ? urgent == 1
                  ? '1 thing needs attention now — it is first below.'
                  : '$urgent things need attention now — they are first below.'
            : outstanding == 0
            ? 'Log a reading whenever you are ready.'
            : 'Nothing is overdue.';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              headline,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: urgent > 0
                    ? AppColors.critical
                    : AppPalette.ink(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
            if (briefing.facts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _HubFactsLine(facts: briefing.facts),
            ],
            for (final step in shown) ...[
              const SizedBox(height: AppSpacing.xs),
              _HubStepRow(action: step),
            ],
            if (steps.length > shown.length) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${steps.length - shown.length} more listed under For you.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textFaint(context),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The counted facts, in a row that wraps: label, then the number in its own
/// colour, with a dot between neighbours. Each is a tap target onto the screen
/// the count came from; none of them is a box.
class _HubFactsLine extends StatelessWidget {
  const _HubFactsLine({required this.facts});

  final List<_HubFact> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < facts.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                '·',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppPalette.textFaint(context),
                ),
              ),
            ),
          _HubFactText(fact: facts[i]),
        ],
      ],
    );
  }
}

class _HubFactText extends StatelessWidget {
  const _HubFactText({required this.fact});

  final _HubFact fact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${fact.label} ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          TextSpan(
            text: fact.value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: fact.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );

    if (fact.onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: text,
      );
    }

    return Semantics(
      button: true,
      label: '${fact.label} ${fact.value}',
      onTap: fact.onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: fact.onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: text,
        ),
      ),
    );
  }
}

/// One step, as a row on the background: icon, what it is, what it says, and
/// a chevron. No fill, no border, no card — the page shows through it.
class _HubStepRow extends StatelessWidget {
  const _HubStepRow({required this.action});

  final _SceneAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(AppSpacing.radiusMd);

    return Semantics(
      button: true,
      label: '${action.title}. ${action.detail}',
      onTap: action.onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: action.onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                const SizedBox(width: AppSpacing.xs),
                Icon(AppIcons.chevronRight, color: action.accent, size: 20),
              ],
            ),
          ),
        ),
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

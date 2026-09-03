part of 'patient_dashboard_view.dart';

/// A tappable row inside a scene — the thing the scene is asking for.
class _SceneAction {
  const _SceneAction({
    required this.icon,
    required this.accent,
    required this.title,
    required this.detail,
    required this.onTap,
    this.priority = 0,
    this.standing = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String detail;
  final VoidCallback onTap;

  /// Higher sorts first, mirroring the priority of the scene the step came
  /// from, so the rows read in the same order as the stream below them.
  final int priority;

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

/// How long a new account is greeted for. Three days: long enough to be seen
/// across a weekend, short enough that it is gone before it is furniture.
const int _welcomeDays = 3;

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
            priority: 100,
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
    final alertPriority = closed != null
        ? (now.difference(closed.createdAt) < const Duration(days: 1) ? 76 : 58)
        : (critical ? 96 : 88);
    final action = _SceneAction(
      priority: alertPriority,
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
        // A fresh answer outranks the routine for a day — the patient was
        // just alarmed by this reading and is owed the reply while they are
        // still wondering about it. After that it settles below the day's work
        // rather than following them around.
        priority: alertPriority,
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
          priority: dose.scheduledAt.isBefore(now) ? 92 : 78,
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
      priority: today ? 84 : 58,
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
    planActions.add(
      _SceneAction(
        priority: 80,
        icon: AppIcons.chat,
        accent: AppColors.info,
        title: 'Reply to ${convo.participant.name}',
        detail:
            '${convo.unreadCount} unread · ${_relativeTime(convo.lastMessage.sentAt)}',
        onTap: () => Navigator.of(
          context,
        ).pushNamed(RouteNames.patientChatThread, arguments: convo.id),
      ),
    );
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
              priority: 80,
              icon: AppIcons.chat,
              accent: AppColors.info,
              title: 'Reply to ${c.participant.name}',
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
  var announcementStepTaken = false;
  for (final ann in AnnouncementsState.instance.live.take(2)) {
    final fresh = now.difference(ann.effectiveAt).inHours < 24;
    if (!announcementStepTaken) {
      announcementStepTaken = true;
      planActions.add(
        _SceneAction(
          priority: fresh ? 68 : 60,
          icon: AppIcons.announcements,
          accent: AppColors.adminPurple,
          title: 'Read announcement',
          detail: ann.title,
          onTap: () => _AnnouncementSheet.show(context, ann),
        ),
      );
    }
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
            priority: fresh ? 72 : 64,
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
      planActions.add(
        _SceneAction(
          priority: fromCareTeam ? 68 : 52,
          icon: AppIcons.document,
          accent: document.category.color,
          title: fromCareTeam ? 'Open new document' : 'Open documents',
          detail: document.title,
          onTap: () =>
              Navigator.of(context).pushNamed(RouteNames.patientDocuments),
        ),
      );
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
              priority: fromCareTeam ? 68 : 52,
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
    planActions.add(
      _SceneAction(
        priority: mealIsToday ? 62 : 48,
        icon: meal.mealType.icon,
        accent: meal.mealType.color,
        title: mealsToday.length > 1
            ? "See today's meals"
            : 'See your ${meal.mealType.label.toLowerCase()}',
        detail: [
          meal.title,
          if (meal.macroSummary.isNotEmpty) meal.macroSummary,
        ].join(' · '),
        onTap: () => mealsToday.length > 1
            ? Navigator.of(context).pushNamed(RouteNames.patientMeals)
            : MealDetailSheet.show(context, meal),
      ),
    );
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
              priority: mealIsToday ? 62 : 48,
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
      priority: allLogged ? 30 : 70,
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
      priority: 55,
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
    planActions.add(
      _SceneAction(
        priority: 60,
        icon: AppIcons.ticket,
        accent: AppColors.info,
        title: 'Open your ticket',
        detail: ticket.subject,
        onTap: () => Navigator.of(context).pushNamed(RouteNames.patientSupport),
      ),
    );
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
            priority: 60,
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
    planActions.add(
      _SceneAction(
        priority: 42,
        icon: AppIcons.user,
        accent: AppColors.brandIndigo,
        title: 'Complete your profile',
        detail: completion.incompleteItems.first.label,
        onTap: () => Navigator.of(context).pushNamed(RouteNames.patientProfile),
      ),
    );
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
            priority: 42,
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

  // --- Welcome: the first three days, and then never again ------------------
  // Dated from the account the server created, not from a flag this app sets,
  // so it cannot follow a returning patient around and cannot be reset by a
  // reinstall. An account whose age is unknown — an older stored session —
  // counts as not new.
  final joinedAt = AuthState.instance.user?.joinedAt;
  final daysHere = AuthState.instance.user?.daysSinceJoining;
  if (joinedAt != null && daysHere != null && daysHere < _welcomeDays) {
    final firstName = AuthState.instance.user?.firstName ?? '';
    planActions.add(
      _SceneAction(
        priority: 74,
        icon: AppIcons.home,
        accent: AppColors.brandIndigo,
        title: 'See what mCare can do',
        detail: 'Vitals, medicines, meals, documents and messages',
        onTap: () => _WelcomeSheet.show(context),
      ),
    );
    scenes.add(
      _HubScene(
        id: 'welcome',
        title: firstName.isEmpty
            ? 'Welcome to mCare'
            : 'Welcome to mCare, $firstName',
        subtitle: daysHere == 0
            ? 'Joined today'
            : 'Day ${daysHere + 1} of $_welcomeDays',
        icon: AppIcons.home,
        accent: AppColors.brandIndigo,
        priority: 74,
        at: joinedAt,
        body:
            'Everything you log here reaches your care team. Take a look at '
            'what the app holds — you can come back to this for three days.',
        actions: [
          _SceneAction(
            priority: 74,
            icon: AppIcons.home,
            accent: AppColors.brandIndigo,
            title: 'See what mCare can do',
            detail: 'Vitals, medicines, meals, documents and messages',
            onTap: () => _WelcomeSheet.show(context),
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

  // The steps read in the same order as the stream: what is wrong, then what
  // is due, then what is merely there.
  planActions.sort((a, b) => b.priority.compareTo(a.priority));

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
/// read. Nothing here is boxed and nothing moves on its own — but every line
/// of it is live, and re-reads its stores the moment they change.
///
/// The shape is what keeps being live from costing the page anything: two
/// lines of text that never wrap, one line of counted facts, then the steps as
/// rows of one fixed shape. A dose being taken, an alert closing or a reading
/// landing swaps a row for a row and rewrites a count in place — it does not
/// re-lay the page out under a thumb already on its way somewhere.
///
/// What the rows hold is the whole app, not one corner of it: an alert, a
/// dose, a visit, an unread message, a notice from the clinic, a new document,
/// today's meal, the reading that is still to be logged, an unfinished
/// profile — and, for a new account's first [_welcomeDays], the welcome. They
/// are ranked, the top of the list is fixed, and the last row is a slot that
/// turns with the calendar day so the quieter things get their turn.
class _PatientTodayHub extends StatelessWidget {
  const _PatientTodayHub({
    required this.appointments,
    required this.doses,
    required this.unreadNotifications,
  });

  final List<Appointment> appointments;
  final List<MedicationDose> doses;
  final int unreadNotifications;

  /// Steps drawn as rows. The rest are not hidden — they are rows in "For you",
  /// and the line under the last one says how many.
  static const _maxSteps = 3;

  /// Which steps get the rows, when there are more than [_maxSteps].
  ///
  /// The top of the list is not negotiable: what is wrong and what is due keep
  /// their places every single time. The last row is a rotating slot, so the
  /// quieter things the app knows — an assigned meal, a new document, a notice
  /// from the clinic — each get their turn on the home page instead of living
  /// permanently below the fold.
  ///
  /// The slot turns with the calendar day, never with a timer: a patient
  /// looking twice in one afternoon sees the same page both times, and a
  /// patient looking every morning sees a different one.
  static List<_SceneAction> _rowsFor(List<_SceneAction> steps, DateTime now) {
    if (steps.length <= _maxSteps) return steps;
    final pinned = steps.take(_maxSteps - 1).toList();
    final rest = steps.skip(_maxSteps - 1).toList();
    final day = DateUtils.dateOnly(now).difference(DateTime(2020)).inDays;
    return [...pinned, rest[day % rest.length]];
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
        final shown = _rowsFor(steps, DateTime.now());
        final hidden = steps.length - shown.length;

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
            // Two lines that never wrap: the head of the block is the same
            // height whatever the day turns out to hold.
            Text(
              headline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
                color: urgent > 0
                    ? AppColors.critical
                    : AppPalette.ink(context),
              ),
            ),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
            if (briefing.facts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _HubFactsLine(facts: briefing.facts),
            ],
            for (final step in shown) _HubStepRow(action: step),
            if (hidden > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '$hidden more listed under For you.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textFaint(context),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The counted facts, on one line that wraps: label, then the number in the
/// colour the number earned — green once every tracked vital is in, amber
/// while a dose is still due. Each is a tap onto the screen it came from.
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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (fact.onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
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
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: text,
        ),
      ),
    );
  }
}

/// One step, as a row on the background: icon, what it is, what it says, and a
/// chevron. No fill, no border, no card — the page shows through it, and the
/// colour is the step's own, so a late dose reads amber without anything
/// having to say "late" twice.
///
/// Every row is [height] tall and clips its two lines, so the strip of steps
/// keeps its height as the day changes underneath it.
class _HubStepRow extends StatelessWidget {
  const _HubStepRow({required this.action});

  final _SceneAction action;

  static const double height = 52;

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
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                _PatientIconDisc(icon: action.icon, color: action.accent),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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

/// What the app holds, for someone who has just been given it.
///
/// Every line opens the real screen rather than describing it — a first look
/// that leaves the patient somewhere useful instead of back where they were.
/// It is reachable for [_welcomeDays] from the home page, and after that from
/// the areas themselves, which is where it was always pointing.
class _WelcomeSheet {
  _WelcomeSheet._();

  static Future<void> show(BuildContext context) {
    final name = AuthState.instance.user?.firstName ?? '';

    return PatientSheet.show<void>(
      context,
      title: name.isEmpty ? 'Welcome to mCare' : 'Welcome, $name',
      subtitle: 'What is here, and where it goes',
      child: Builder(
        builder: (sheetContext) {
          void openAfterClosing(VoidCallback open) {
            Navigator.of(sheetContext).pop();
            open();
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Everything you record here reaches your care team, and '
                'everything they send you arrives in the same place.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.45),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final entry in _entries(context))
                _HubStepRow(
                  action: _SceneAction(
                    icon: entry.icon,
                    accent: entry.accent,
                    title: entry.title,
                    detail: entry.detail,
                    onTap: () => openAfterClosing(entry.open),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static List<_WelcomeEntry> _entries(BuildContext context) {
    void go(String route) => Navigator.of(context).pushNamed(route);
    return [
      _WelcomeEntry(
        icon: AppIcons.vitals,
        accent: AppColors.brandIndigo,
        title: 'Vitals',
        detail: 'Log a reading — your care team reads today\'s numbers',
        open: () => SubmitVitalSheet.show(context),
      ),
      _WelcomeEntry(
        icon: AppIcons.medication,
        accent: AppColors.success,
        title: 'Medications',
        detail: 'What to take, when, and what you have taken',
        open: () => go(RouteNames.patientMedications),
      ),
      _WelcomeEntry(
        icon: AppIcons.meals,
        accent: AppColors.warning,
        title: 'Meals',
        detail: 'Meal plans your care team assigns you',
        open: () => go(RouteNames.patientMeals),
      ),
      _WelcomeEntry(
        icon: AppIcons.appointment,
        accent: AppColors.bpPurple,
        title: 'Appointments',
        detail: 'Visits, in person or by video',
        open: () => go(RouteNames.patientAppointments),
      ),
      _WelcomeEntry(
        icon: AppIcons.document,
        accent: AppColors.info,
        title: 'Documents',
        detail: 'Results and letters, yours and theirs',
        open: () => go(RouteNames.patientDocuments),
      ),
      _WelcomeEntry(
        icon: AppIcons.chat,
        accent: AppColors.info,
        title: 'Messages',
        detail: 'Talk to your care team',
        open: () => go(RouteNames.patientMessages),
      ),
      _WelcomeEntry(
        icon: AppIcons.user,
        accent: AppColors.adminPurple,
        title: 'Your profile',
        detail: 'The details a care team should not have to guess',
        open: () => go(RouteNames.patientProfile),
      ),
    ];
  }
}

class _WelcomeEntry {
  const _WelcomeEntry({
    required this.icon,
    required this.accent,
    required this.title,
    required this.detail,
    required this.open,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String detail;
  final VoidCallback open;
}

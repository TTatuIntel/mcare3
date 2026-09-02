part of 'patient_dashboard_view.dart';

/// The patient home is intentionally short: search, quick actions, then one
/// prioritised stream. Status information is not repeated in separate cards.
class _PatientHomeLayout extends StatelessWidget {
  const _PatientHomeLayout({
    required this.appointments,
    required this.doses,
    required this.unreadNotifications,
  });

  final List<Appointment> appointments;
  final List<MedicationDose> doses;
  final int unreadNotifications;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final quickActions = _PatientQuickActions(
          appointments: appointments,
          doses: doses,
        );
        final forYou = _PatientForYouSection(
          appointments: appointments,
          doses: doses,
          unreadNotifications: unreadNotifications,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const StaggeredEntry(index: 0, child: PatientDateHeader()),
            const SizedBox(height: AppSpacing.md),
            StaggeredEntry(
              index: 1,
              child: _PatientTodayHub(
                appointments: appointments,
                doses: doses,
                unreadNotifications: unreadNotifications,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const StaggeredEntry(index: 2, child: _PatientFeatureSearch()),
            if (ReportConsentsState.instance.hasAwaiting) ...[
              const SizedBox(height: AppSpacing.md),
              const StaggeredEntry(
                key: ValueKey('patient-sharing-request'),
                index: 3,
                child: _PatientSharingRequestCard(),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: StaggeredEntry(index: 3, child: quickActions),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(
                    flex: 7,
                    child: StaggeredEntry(index: 4, child: forYou),
                  ),
                ],
              )
            else ...[
              StaggeredEntry(index: 3, child: quickActions),
              const SizedBox(height: AppSpacing.lg),
              StaggeredEntry(index: 4, child: forYou),
            ],
            const SizedBox(height: AppSpacing.xxl),
          ],
        );
      },
    );
  }
}

class _PatientFeatureSearch extends StatelessWidget {
  const _PatientFeatureSearch();

  Future<void> _open(BuildContext context) async {
    final result = await showSearch<_PatientSearchEntry?>(
      context: context,
      delegate: _PatientSearchDelegate(),
    );
    if (result != null && context.mounted) result.open(context);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search mCare features',
      child: GlassCard(
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        shadow: const [],
        onTap: () => _open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                const Icon(
                  AppIcons.search,
                  size: 22,
                  color: AppColors.brandIndigo,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Search vitals, appointments, documents…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ),
                Icon(
                  AppIcons.chevronRight,
                  size: 20,
                  color: AppPalette.textFaint(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientSearchEntry {
  const _PatientSearchEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.keywords,
    required this.icon,
    required this.color,
    this.route,
  });

  final String id;
  final String title;
  final String description;
  final String keywords;
  final IconData icon;
  final Color color;
  final String? route;

  bool matches(String value) {
    final q = value.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$title $description $keywords'.toLowerCase().contains(q);
  }

  void open(BuildContext context) {
    if (id == 'meals') {
      _openPatientMeals(context);
      return;
    }
    final destination = route;
    if (destination != null) Navigator.of(context).pushNamed(destination);
  }
}

const _patientSearchEntries = <_PatientSearchEntry>[
  _PatientSearchEntry(
    id: 'vitals',
    title: 'Vitals',
    description: 'Log readings and review trends',
    keywords: 'blood pressure heart rate glucose temperature oxygen weight',
    icon: AppIcons.vitals,
    color: AppColors.brandIndigo,
    route: RouteNames.patientVitals,
  ),
  _PatientSearchEntry(
    id: 'appointments',
    title: 'Appointments',
    description: 'Book or review a visit',
    keywords: 'visit doctor booking schedule consultation',
    icon: AppIcons.appointment,
    color: AppColors.bpPurple,
    route: RouteNames.patientAppointments,
  ),
  _PatientSearchEntry(
    id: 'medications',
    title: 'Medications',
    description: 'View doses and prescriptions',
    keywords: 'medicine drugs dose pills pharmacy prescription',
    icon: AppIcons.medication,
    color: AppColors.glucoseAmber,
    route: RouteNames.patientMedications,
  ),
  _PatientSearchEntry(
    id: 'documents',
    title: 'Documents & uploads',
    description: 'Open results, reports and files',
    keywords: 'upload lab result imaging record file report',
    icon: AppIcons.document,
    color: AppColors.info,
    route: RouteNames.patientDocuments,
  ),
  _PatientSearchEntry(
    id: 'meals',
    title: 'Meals',
    description: 'Review your assigned meal plan',
    keywords: 'food nutrition diet breakfast lunch dinner',
    icon: AppIcons.meals,
    color: AppColors.success,
  ),
  _PatientSearchEntry(
    id: 'emergency',
    title: 'Emergency SOS',
    description: 'Get urgent help now',
    keywords: 'emergency urgent sos danger help',
    icon: AppIcons.sos,
    color: AppColors.critical,
    route: RouteNames.patientSos,
  ),
  _PatientSearchEntry(
    id: 'notifications',
    title: 'Alerts & activity',
    description: 'Read care updates and reminders',
    keywords: 'notifications news activities announcements updates',
    icon: AppIcons.notifications,
    color: AppColors.warning,
    route: RouteNames.patientNotifications,
  ),
  _PatientSearchEntry(
    id: 'messages',
    title: 'Messages',
    description: 'Chat with your care team',
    keywords: 'conversation inbox doctor nurse chat',
    icon: AppIcons.chat,
    color: AppColors.info,
    route: RouteNames.patientMessages,
  ),
  _PatientSearchEntry(
    id: 'care-team',
    title: 'Care team',
    description: 'See your doctors and providers',
    keywords: 'doctor provider nurse clinician team',
    icon: AppIcons.careTeam,
    color: AppColors.doctorGreen,
    route: RouteNames.patientCareTeam,
  ),
  _PatientSearchEntry(
    id: 'support',
    title: 'Support',
    description: 'Ask for help with mCare',
    keywords: 'ticket problem technical help',
    icon: AppIcons.support,
    color: AppColors.info,
    route: RouteNames.patientSupport,
  ),
  _PatientSearchEntry(
    id: 'profile',
    title: 'Profile',
    description: 'Update personal and health details',
    keywords: 'account personal health information contact',
    icon: AppIcons.profile,
    color: AppColors.doctorGreen,
    route: RouteNames.patientProfile,
  ),
  _PatientSearchEntry(
    id: 'settings',
    title: 'Settings',
    description: 'Privacy, language and appearance',
    keywords: 'preferences security theme notifications language privacy',
    icon: AppIcons.settings,
    color: AppColors.weightSlate,
    route: RouteNames.patientSettings,
  ),
];

class _PatientSearchDelegate extends SearchDelegate<_PatientSearchEntry?> {
  @override
  String get searchFieldLabel => 'What do you need?';

  @override
  List<Widget>? buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: 'Clear search',
        onPressed: () => query = '',
        icon: const Icon(AppIcons.close),
      ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    tooltip: 'Back',
    onPressed: () => close(context, null),
    icon: const Icon(AppIcons.back),
  );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final matches = _patientSearchEntries.where((item) => item.matches(query));
    if (matches.isEmpty) {
      return EmptyStateView(
        icon: AppIcons.search,
        title: 'No match found',
        message: 'Try a word like vitals, appointment, upload or emergency.',
        compact: true,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final item = matches.elementAt(index);
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            side: BorderSide(color: AppPalette.border(context)),
          ),
          tileColor: AppPalette.surface(context),
          leading: _PatientIconDisc(icon: item.icon, color: item.color),
          title: Text(item.title),
          subtitle: Text(item.description),
          trailing: const Icon(AppIcons.chevronRight),
          onTap: () => close(context, item),
        );
      },
    );
  }
}

void _openPatientMeals(BuildContext context) {
  final today = MealPlansState.instance.assignedToday;
  final meal = today.isNotEmpty ? today.first : MealPlansState.instance.latest;
  if (meal == null) {
    AppToast.info(context, 'No meal plan has been assigned yet.');
    return;
  }
  _MealPlanSheet.show(context, meal);
}

class _PatientQuickActions extends StatelessWidget {
  const _PatientQuickActions({required this.appointments, required this.doses});

  final List<Appointment> appointments;
  final List<MedicationDose> doses;

  @override
  Widget build(BuildContext context) {
    final pendingDoses = doses.where(
      (dose) => dose.status == DoseStatus.pending,
    );
    final mealsToday = MealPlansState.instance.assignedToday.length;
    final actions = <_PatientQuickAction>[
      _PatientQuickAction(
        label: 'Appointments',
        detail: appointments.isEmpty
            ? 'Book a visit'
            : '${appointments.length} upcoming',
        icon: AppIcons.appointment,
        color: AppColors.bpPurple,
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.patientAppointments),
      ),
      _PatientQuickAction(
        label: 'Medications',
        detail: pendingDoses.isEmpty
            ? 'View medicines'
            : '${pendingDoses.length} due today',
        icon: AppIcons.medication,
        color: AppColors.glucoseAmber,
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.patientMedications),
      ),
      _PatientQuickAction(
        label: 'Log vital',
        detail: 'Add a reading',
        icon: AppIcons.vitals,
        color: AppColors.brandIndigo,
        onTap: () => SubmitVitalSheet.show(context),
      ),
      _PatientQuickAction(
        label: 'Meals',
        detail: mealsToday == 0 ? 'Meal plan' : '$mealsToday for today',
        icon: AppIcons.meals,
        color: AppColors.success,
        onTap: () => _openPatientMeals(context),
      ),
      _PatientQuickAction(
        label: 'Documents',
        detail: 'View & upload',
        icon: AppIcons.upload,
        color: AppColors.info,
        onTap: () =>
            Navigator.of(context).pushNamed(RouteNames.patientDocuments),
      ),
      _PatientQuickAction(
        label: 'Emergency',
        detail: 'Get help now',
        icon: AppIcons.sos,
        color: AppColors.critical,
        onTap: () => Navigator.of(context).pushNamed(RouteNames.patientSos),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel(title: 'Quick actions', icon: AppIcons.add),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 680
                ? 6
                : constraints.maxWidth >= 340
                ? 3
                : 2;
            const gap = AppSpacing.sm;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: width,
                    child: _PatientQuickActionTile(action: action),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PatientQuickAction {
  const _PatientQuickAction({
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _PatientQuickActionTile extends StatelessWidget {
  const _PatientQuickActionTile({required this.action});

  final _PatientQuickAction action;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${action.label}. ${action.detail}',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        shadow: const [],
        onTap: action.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PatientIconDisc(icon: action.icon, color: action.color),
            const SizedBox(height: AppSpacing.sm),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              action.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  static const _collapsedCount = 5;
  bool _showAll = false;

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
        final items =
            _buildHubScenes(
                  context,
                  appointments: widget.appointments,
                  doses: widget.doses,
                  unreadNotifications: widget.unreadNotifications,
                )
                .where((scene) => scene.id != 'plan' && scene.id != 'welcome')
                .toList();
        final visible = _showAll ? items : items.take(_collapsedCount).toList();
        final hidden = items.length - visible.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(
              title: 'For you',
              icon: AppIcons.activity,
              trailing: items.isEmpty
                  ? null
                  : '${items.length} update${items.length == 1 ? '' : 's'}',
            ),
            GlassCard(
              padding: EdgeInsets.zero,
              shadow: const [],
              child: items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: EmptyStateView(
                        icon: AppIcons.check,
                        title: 'You are all caught up',
                        message:
                            'New care updates and recommendations will appear here.',
                        actionLabel: 'Log a vital',
                        onAction: () => SubmitVitalSheet.show(context),
                        compact: true,
                      ),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < visible.length; i++) ...[
                          _PatientForYouRow(scene: visible[i]),
                          if (i != visible.length - 1)
                            Divider(
                              height: 1,
                              color: AppPalette.border(context),
                            ),
                        ],
                        if (hidden > 0 || _showAll) ...[
                          Divider(height: 1, color: AppPalette.border(context)),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _showAll = !_showAll),
                            icon: Icon(
                              _showAll
                                  ? AppIcons.expandLess
                                  : AppIcons.expandMore,
                              size: 18,
                            ),
                            label: Text(
                              _showAll ? 'Show less' : 'Show $hidden more',
                            ),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PatientForYouRow extends StatelessWidget {
  const _PatientForYouRow({required this.scene});

  final _HubScene scene;

  String get _kind {
    if (scene.urgent) return 'Alert';
    if (scene.id.startsWith('ann_')) return 'News';
    if (scene.id == 'profile' || scene.id == 'progress') return 'Recommended';
    return 'Activity';
  }

  @override
  Widget build(BuildContext context) {
    final action = scene.actions.isEmpty ? null : scene.actions.first;
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _PatientIconDisc(icon: scene.icon, color: scene.accent),
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
                        scene.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scene.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusPill,
                        ),
                      ),
                      child: Text(
                        _kind,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scene.accent,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  scene.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppPalette.textMuted(context),
                  ),
                ),
                if ((scene.body ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    scene.body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppPalette.ink(context),
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(AppIcons.chevronRight, color: scene.accent, size: 20),
          ],
        ],
      ),
    );

    if (action == null) return body;
    return Semantics(
      button: true,
      label: '${scene.title}. ${scene.subtitle}',
      child: InkWell(onTap: action.onTap, child: body),
    );
  }
}

/// Home "Record a vital" board.
///
/// Shows every vital the patient tracks (care-team assigned first, then the
/// ones they self-assigned), each carrying its latest reading, status and
/// trend so logging is a decision, not a guess. The board is also the entry
/// point for self-assignment: "Manage" and the trailing add tile both open
/// [VitalPreferencesSheet], where optional vitals can be switched on.
/// General statistics for the tracked vitals, derived only from what the
/// stores already hold. These stay visible even when the board is collapsed,
/// so home always answers "am I on top of my vitals?" in one glance.
class _PatientVitalStats {
  const _PatientVitalStats({
    required this.tracked,
    required this.loggedToday,
    required this.needsAttention,
    required this.lastLoggedAt,
  });

  factory _PatientVitalStats.from(List<VitalKey> tracked) {
    final trackedSet = tracked.toSet();
    var needsAttention = 0;
    for (final vital in tracked) {
      if (NotificationState.instance.vitalAlertFor(vital) != null) {
        needsAttention++;
        continue;
      }
      final risk = VitalsState.instance.latestOf(vital)?.risk;
      if (risk == RiskLevel.critical || risk == RiskLevel.warning) {
        needsAttention++;
      }
    }

    final now = DateTime.now();
    var loggedToday = 0;
    DateTime? lastLoggedAt;
    for (final reading in VitalsState.instance.all) {
      if (!trackedSet.contains(reading.vital)) continue;
      if (DateUtils.isSameDay(reading.recordedAt, now)) loggedToday++;
      if (lastLoggedAt == null || reading.recordedAt.isAfter(lastLoggedAt)) {
        lastLoggedAt = reading.recordedAt;
      }
    }

    return _PatientVitalStats(
      tracked: tracked.length,
      loggedToday: loggedToday,
      needsAttention: needsAttention,
      lastLoggedAt: lastLoggedAt,
    );
  }

  final int tracked;
  final int loggedToday;
  final int needsAttention;
  final DateTime? lastLoggedAt;

  bool get hasAttention => needsAttention > 0;

  Color get accent => hasAttention ? AppColors.warning : AppColors.brandIndigo;

  String get headline {
    if (tracked == 0) return 'Nothing tracked yet';
    if (hasAttention) {
      return '$needsAttention vital${needsAttention == 1 ? '' : 's'} to review';
    }
    if (loggedToday > 0) return 'Vitals logged today';
    return 'Vitals are up to date';
  }

  /// `_relativeTime` is written to start a sentence. Mid-sentence only its two
  /// word forms need lowering — a month name has to keep its capital.
  String _lastLoggedLabel(DateTime at) {
    final label = _relativeTime(at);
    return switch (label) {
      'Just now' => 'just now',
      'Yesterday' => 'yesterday',
      _ => label,
    };
  }

  String get detail {
    if (tracked == 0) return 'Choose the vitals you want to record';
    final at = lastLoggedAt;
    final last = at == null
        ? 'nothing logged yet'
        : 'last logged ${_lastLoggedLabel(at)}';
    return '$tracked tracked · $last';
  }
}

/// Home's vitals board. It is a drop-down: collapsed by default so the page
/// stays short, with the statistics strip and the shortcut to the Vitals page
/// always on screen. Expanding reveals the per-vital log tiles unchanged.
class _PatientVitalShortcuts extends StatefulWidget {
  const _PatientVitalShortcuts();

  @override
  State<_PatientVitalShortcuts> createState() => _PatientVitalShortcutsState();
}

class _PatientVitalShortcutsState extends State<_PatientVitalShortcuts> {
  /// Keep home scannable — the rest stay one tap away on the Vitals screen.
  static const _maxTiles = 6;

  bool _expanded = false;

  /// Alerting first, then critical / watch, then most recently updated. The
  /// reading a clinician would look at first is the one nearest the thumb.
  static List<VitalKey> _ordered(List<VitalKey> tracked) {
    int priority(VitalKey key) {
      if (NotificationState.instance.vitalAlertFor(key) != null) return 0;
      return switch (VitalsState.instance.latestOf(key)?.risk) {
        RiskLevel.critical => 1,
        RiskLevel.warning => 2,
        _ => 3,
      };
    }

    return tracked.toList()..sort((a, b) {
      final byPriority = priority(a).compareTo(priority(b));
      if (byPriority != 0) return byPriority;
      final assignedA = VitalsState.instance.isAssigned(a);
      final assignedB = VitalsState.instance.isAssigned(b);
      if (assignedA != assignedB) return assignedA ? -1 : 1;
      final ra = VitalsState.instance.latestOf(a)?.recordedAt;
      final rb = VitalsState.instance.latestOf(b)?.recordedAt;
      if (ra == null && rb == null) return a.index.compareTo(b.index);
      if (ra == null) return 1;
      if (rb == null) return -1;
      return rb.compareTo(ra);
    });
  }

  static int _columnsFor(double width) {
    if (width >= 960) return 4;
    if (width >= 620) return 3;
    return 2;
  }

  static VitalReading? _previousReading(VitalKey vital) {
    final history = VitalsState.instance.forVital(vital);
    return history.length > 1 ? history[1] : null;
  }

  void _openVitalsPage() =>
      Navigator.of(context).pushNamed(RouteNames.patientVitals);

  void _toggle() => setState(() => _expanded = !_expanded);

  Widget _board(List<VitalKey> tracked, {required bool canAddMore}) {
    final state = VitalsState.instance;
    final shown = tracked.take(_maxTiles).toList();
    final hidden = tracked.length - shown.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth);
        const gap = AppSpacing.sm;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        final tiles = <Widget>[
          for (final vital in shown)
            _PatientVitalCard(
              vital: vital,
              reading: state.latestOf(vital),
              previous: _previousReading(vital),
              alert: NotificationState.instance.vitalAlertFor(vital),
              assigned: state.isAssigned(vital),
              onLog: () => SubmitVitalSheet.show(context, initial: vital),
              onOpen: () => openVitalDetail(context, vital),
            ),
          if (canAddMore || hidden > 0)
            _PatientAddVitalCard(
              label: canAddMore ? 'Add a vital' : 'See all vitals',
              detail: hidden > 0
                  ? '$hidden more tracked · tap to review'
                  : 'Track what matters to you',
              onTap: canAddMore
                  ? () => VitalPreferencesSheet.show(context)
                  : _openVitalsPage,
            ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileWidth, child: tile),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = VitalsState.instance;
    final tracked = _ordered(state.tracked.toList());
    final stats = _PatientVitalStats.from(tracked);
    final canAddMore = state.selectableVitals.any(
      (v) => !state.tracked.contains(v),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          title: 'Record a vital',
          icon: AppIcons.vitals,
          trailing: tracked.isEmpty ? null : '${tracked.length} tracked',
          actionLabel: 'Vitals',
          onAction: _openVitalsPage,
        ),
        if (tracked.isEmpty)
          GlassCard(
            child: EmptyStateView(
              icon: AppIcons.vitals,
              title: 'Nothing tracked yet',
              message:
                  'Choose the vitals you want to record. Anything your care '
                  'team assigns is added here automatically.',
              actionLabel: 'Choose vitals',
              onAction: () => VitalPreferencesSheet.show(context),
              compact: true,
            ),
          )
        else
          GlassCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PatientVitalBoardHeader(
                  stats: stats,
                  expanded: _expanded,
                  onToggle: _toggle,
                ),
                const SizedBox(height: AppSpacing.sm),
                _PatientVitalStatsStrip(
                  stats: stats,
                  onOpenVitals: _openVitalsPage,
                ),
                const SizedBox(height: AppSpacing.md),
                _PatientVitalBoardActions(
                  expanded: _expanded,
                  onToggle: _toggle,
                  onOpenVitals: _openVitalsPage,
                ),
                // Collapsed is the default. The tiles are built only once the
                // patient asks for them — AnimatedSize animates the height
                // without keeping the closed board in the tree.
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: _board(tracked, canAddMore: canAddMore),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Collapsed summary line — tapping anywhere on it opens or closes the board.
class _PatientVitalBoardHeader extends StatelessWidget {
  const _PatientVitalBoardHeader({
    required this.stats,
    required this.expanded,
    required this.onToggle,
  });

  final _PatientVitalStats stats;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = stats.accent;

    return Semantics(
      button: true,
      expanded: expanded,
      label: '${stats.headline}. ${stats.detail}.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                _PatientIconDisc(
                  icon: stats.hasAttention ? AppIcons.alert : AppIcons.vitals,
                  color: accent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stats.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stats.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          height: 1.2,
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Icon(AppIcons.expandMore, size: 22, color: accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// General statistics for vitals — visible whether or not the board is open.
class _PatientVitalStatsStrip extends StatelessWidget {
  const _PatientVitalStatsStrip({
    required this.stats,
    required this.onOpenVitals,
  });

  final _PatientVitalStats stats;
  final VoidCallback onOpenVitals;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        children: [
          PatientHeroStat(
            label: 'Tracked',
            value: '${stats.tracked}',
            onTap: onOpenVitals,
          ),
          const PatientHeroStatDivider(),
          PatientHeroStat(
            label: 'Logged today',
            value: '${stats.loggedToday}',
            accent: stats.loggedToday > 0 ? AppColors.success : null,
            onTap: onOpenVitals,
          ),
          const PatientHeroStatDivider(),
          PatientHeroStat(
            label: 'Need review',
            value: '${stats.needsAttention}',
            accent: stats.hasAttention ? AppColors.warning : null,
            onTap: onOpenVitals,
          ),
        ],
      ),
    );
  }
}

/// The two ways out of the collapsed card: open the full Vitals page, or open
/// the tile board in place.
class _PatientVitalBoardActions extends StatelessWidget {
  const _PatientVitalBoardActions({
    required this.expanded,
    required this.onToggle,
    required this.onOpenVitals,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpenVitals;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppButton(
            label: 'Go to vitals',
            icon: AppIcons.vitals,
            size: AppButtonSize.sm,
            expand: true,
            onPressed: onOpenVitals,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: AppButton(
            label: expanded ? 'Hide board' : 'Quick log',
            icon: expanded ? AppIcons.expandLess : AppIcons.expandMore,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            expand: true,
            onPressed: onToggle,
          ),
        ),
      ],
    );
  }
}

/// One vital on the home board: latest value, status, trend and a log action.
class _PatientVitalCard extends StatelessWidget {
  const _PatientVitalCard({
    required this.vital,
    required this.reading,
    required this.previous,
    required this.alert,
    required this.assigned,
    required this.onLog,
    required this.onOpen,
  });

  final VitalKey vital;
  final VitalReading? reading;
  final VitalReading? previous;
  final AppNotification? alert;
  final bool assigned;
  final VoidCallback onLog;
  final VoidCallback onOpen;

  /// Signed change against the previous reading, or null when there is no
  /// comparison to make. Blood pressure trends on its systolic value.
  double? get _delta {
    final current = reading;
    final before = previous;
    if (current == null || before == null) return null;
    final diff = current.value - before.value;
    return diff.abs() < 0.05 ? 0 : diff;
  }

  String _formatDelta(double delta) {
    final magnitude = delta.abs();
    final text = (vital == VitalKey.temperature || vital == VitalKey.weight)
        ? magnitude.toStringAsFixed(1)
        : magnitude.toStringAsFixed(0);
    return '${delta > 0 ? '+' : '-'}$text';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = vital.accent;
    final risk = reading?.risk ?? RiskLevel.unknown;
    final delta = _delta;
    final statusColor = alert != null ? alert!.kind.tint : risk.color;
    final calm = risk == RiskLevel.normal || risk == RiskLevel.unknown;

    return GlassCard(
      onTap: onLog,
      padding: const EdgeInsets.all(AppSpacing.md),
      background: accent.withValues(alpha: 0.055),
      border: Border.all(
        color: calm && alert == null
            ? accent.withValues(alpha: 0.18)
            : statusColor.withValues(alpha: 0.38),
        width: risk == RiskLevel.critical ? 1.4 : 1,
      ),
      child: Semantics(
        button: true,
        label:
            '${vital.label}, '
            '${reading == null ? 'no reading yet' : '${reading!.formatValue()} ${vital.unit}, ${risk.label}'}. '
            'Log a reading.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _PatientIconDisc(icon: vital.icon, color: accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        vital.shortLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                      Text(
                        assigned ? 'Care team' : 'Self-tracked',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: assigned
                              ? accent
                              : AppPalette.textFaint(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (delta != null && delta != 0) ...[
                  const SizedBox(width: 2),
                  Icon(
                    delta > 0 ? AppIcons.trendUp : AppIcons.trendDown,
                    size: 14,
                    color: AppPalette.textMuted(context),
                  ),
                  const SizedBox(width: 1),
                  Text(
                    _formatDelta(delta),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textMuted(context),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: reading?.formatValue() ?? '—',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: reading == null
                            ? AppPalette.textFaint(context)
                            : accent,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    TextSpan(
                      text: ' ${vital.unit}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: RiskBadge(
                risk: risk,
                dense: true,
                label: alert != null ? 'Alert' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: reading == null ? onLog : onOpen,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      reading == null
                          ? 'Not logged yet'
                          : _relativeTime(reading!.recordedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: AppPalette.textMuted(context),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.add, size: 13, color: accent),
                      const SizedBox(width: 2),
                      Text(
                        'Log',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Trailing tile on the vitals board — patient self-assignment lives here.
class _PatientAddVitalCard extends StatelessWidget {
  const _PatientAddVitalCard({
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = AppColors.brandIndigo;

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      background: AppPalette.surfaceAlt(context),
      border: Border.all(color: accent.withValues(alpha: 0.30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _PatientIconDisc(icon: AppIcons.add, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            detail,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              height: 1.3,
              color: AppPalette.textMuted(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatientNextDoseCard extends StatelessWidget {
  const _PatientNextDoseCard({required this.doses});

  final List<MedicationDose> doses;

  @override
  Widget build(BuildContext context) {
    final pending = doses.where((d) => d.status == DoseStatus.pending).toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    final dose = pending.isEmpty ? null : pending.first;

    return _PatientNextCard(
      eyebrow: dose == null ? 'Medication plan' : 'Next medication',
      title:
          dose?.name ??
          (doses.isEmpty
              ? 'No doses scheduled today'
              : 'Today\'s doses logged'),
      detail: dose == null
          ? 'Open medications to review your plan'
          : '${dose.dosage} · ${DateFormat.jm().format(dose.scheduledAt)}',
      icon: AppIcons.medication,
      color: AppColors.success,
      actionLabel: dose == null ? 'View plan' : 'Log dose',
      onTap: () {
        if (dose != null) {
          LogDoseSheet.show(context, dose);
        } else {
          Navigator.of(context).pushNamed(RouteNames.patientMedications);
        }
      },
    );
  }
}

class _PatientNextVisitCard extends StatelessWidget {
  const _PatientNextVisitCard({required this.appointments});

  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    final visit = appointments.isEmpty ? null : appointments.first;
    return _PatientNextCard(
      eyebrow: 'Next appointment',
      title: visit?.doctorName ?? 'No upcoming appointment',
      detail: visit == null
          ? 'Book or review your visits'
          : _patientVisitTime(visit.scheduledAt),
      icon: AppIcons.appointment,
      color: AppColors.bpPurple,
      actionLabel: visit == null ? 'Appointments' : 'View details',
      onTap: () => Navigator.of(context).pushNamed(
        visit == null
            ? RouteNames.patientAppointments
            : RouteNames.patientAppointmentDetail,
        arguments: visit?.id,
      ),
    );
  }
}

class _PatientNextCard extends StatelessWidget {
  const _PatientNextCard({
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.actionLabel,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          final content = Row(
            children: [
              _PatientIconDisc(icon: icon, color: color, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: AppSpacing.md),
                AppButton(
                  label: actionLabel,
                  onPressed: onTap,
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.secondary,
                  trailingIcon: AppIcons.chevronRight,
                ),
              ],
            ],
          );
          if (!compact) return content;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              content,
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: actionLabel,
                onPressed: onTap,
                size: AppButtonSize.sm,
                variant: AppButtonVariant.secondary,
                trailingIcon: AppIcons.chevronRight,
                expand: true,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// End-of-page emergency + help block.
///
/// It is the LAST card on the patient home page on purpose: the fastest place
/// to reach with a thumb, and the single home-screen entry point for SOS. The
/// account sheet deliberately no longer repeats an "Emergency SOS" row (see
/// `ProfileNavigation.menuFor`) so the action lives in exactly one place per
/// surface — here, and on the Care tab.
///
/// Everything shown is derived from existing stores ([SosState],
/// [ProfileState]); the card never invents emergency state.
class _PatientHelpCard extends StatelessWidget {
  const _PatientHelpCard();

  void _open(BuildContext context, String route) =>
      Navigator.of(context).pushNamed(route);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([SosState.instance, ProfileState.instance]),
      builder: (context, _) {
        final theme = Theme.of(context);
        final active = SosState.instance.hasActiveSos;
        final contacts = SosState.instance.contacts.length;
        final shareLocation =
            ProfileState.instance.health?.locationConsent ?? false;
        final accent = active ? AppColors.critical : AppColors.brandIndigo;

        return GlassCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          background: accent.withValues(alpha: 0.04),
          border: Border.all(
            color: accent.withValues(alpha: active ? 0.38 : 0.16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _PatientIconDisc(icon: AppIcons.sos, color: accent),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active ? 'SOS is active' : 'Need help now?',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          active
                              ? 'Your care team has been alerted and is responding.'
                              : 'Emergency help and your care team, one tap away.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppPalette.textMuted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: active ? 'View SOS status' : 'Emergency SOS',
                icon: AppIcons.sos,
                trailingIcon: AppIcons.chevronRight,
                variant: active
                    ? AppButtonVariant.secondary
                    : AppButtonVariant.danger,
                size: AppButtonSize.lg,
                expand: true,
                onPressed: () => _open(context, RouteNames.patientSos),
              ),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth >= 420;
                  final care = AppButton(
                    label: 'Contact care team',
                    icon: AppIcons.careTeam,
                    trailingIcon: horizontal ? null : AppIcons.chevronRight,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () => _open(context, RouteNames.patientCareTeam),
                  );
                  final support = AppButton(
                    label: 'Support',
                    icon: AppIcons.support,
                    trailingIcon: horizontal ? null : AppIcons.chevronRight,
                    variant: AppButtonVariant.secondary,
                    expand: true,
                    onPressed: () => _open(context, RouteNames.patientSupport),
                  );
                  if (horizontal) {
                    return Row(
                      children: [
                        Expanded(child: care),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: support),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      care,
                      const SizedBox(height: AppSpacing.sm),
                      support,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _PatientHelpMeta(
                contacts: contacts,
                shareLocation: shareLocation,
                onManage: () => _open(context, RouteNames.patientSos),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Readiness line under the help actions — what actually happens on SOS.
class _PatientHelpMeta extends StatelessWidget {
  const _PatientHelpMeta({
    required this.contacts,
    required this.shareLocation,
    required this.onManage,
  });

  final int contacts;
  final bool shareLocation;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final muted = AppPalette.textMuted(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: muted);

    // Flexible, not a bare Text: a Wrap hands each child the full line width,
    // so a label that measures wider than the card (longer contact counts, a
    // wider font, a narrow phone) overflows the row instead of wrapping.
    Widget chip(IconData icon, String text, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip(
          contacts > 0 ? AppIcons.check : AppIcons.alert,
          contacts > 0
              ? '$contacts emergency contact${contacts == 1 ? '' : 's'}'
              : 'No emergency contacts yet',
          contacts > 0 ? AppColors.success : AppColors.warning,
        ),
        chip(
          AppIcons.location,
          shareLocation ? 'Location shared on SOS' : 'Location sharing off',
          shareLocation ? AppColors.success : muted,
        ),
        InkWell(
          onTap: onManage,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(
              'Manage',
              style: style?.copyWith(
                color: AppColors.brandIndigo,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PatientIconDisc extends StatelessWidget {
  const _PatientIconDisc({
    required this.icon,
    required this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.45),
    );
  }
}

String _patientVisitTime(DateTime scheduledAt) {
  final now = DateTime.now();
  final day = DateUtils.isSameDay(scheduledAt, now)
      ? 'Today'
      : DateUtils.isSameDay(scheduledAt, now.add(const Duration(days: 1)))
      ? 'Tomorrow'
      : DateFormat.MMMEd().format(scheduledAt);
  return '$day · ${DateFormat.jm().format(scheduledAt)}';
}

/// Home prompt for outstanding record-sharing requests.
///
/// Consent used to travel on a single notification; once that was read there
/// was no way back to the approval screen and the request expired unanswered.
/// This card stays until the patient actually approves or declines.
class _PatientSharingRequestCard extends StatelessWidget {
  const _PatientSharingRequestCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final awaiting = ReportConsentsState.instance.awaiting;
    if (awaiting.isEmpty) return const SizedBox.shrink();

    final first = awaiting.first;
    final more = awaiting.length - 1;
    const accent = AppColors.warning;

    final detail = more > 0
        ? '${awaiting.length} requests need your decision'
        : 'For ${first.purpose}'
              '${first.requestedByName == null ? '' : ' · asked by ${first.requestedByName}'}';

    return GlassCard(
      onTap: () =>
          Navigator.of(context).pushNamed(RouteNames.patientReportConsents),
      padding: const EdgeInsets.all(AppSpacing.md),
      background: AppPalette.warningSoft(context),
      border: Border.all(color: accent.withValues(alpha: 0.40)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const _PatientIconDisc(icon: AppIcons.document, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      more > 0 ? 'Approve sharing of your record' : first.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        height: 1.3,
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Nothing is shared until you decide.',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              height: 1.3,
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Review request${more > 0 ? 's' : ''}',
            icon: AppIcons.chevronRight,
            size: AppButtonSize.sm,
            expand: true,
            onPressed: () => Navigator.of(
              context,
            ).pushNamed(RouteNames.patientReportConsents),
          ),
        ],
      ),
    );
  }
}

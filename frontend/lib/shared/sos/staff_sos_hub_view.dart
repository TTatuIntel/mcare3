import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/sos_follow_up_api.dart';
import '../../core/web/web_platform.dart' as web_platform;
import '../alerts/alert_return_point.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/user_role.dart';
import '../navigation/sos_navigation.dart';
import '../navigation/staff_destinations.dart';
import '../services/admin_sos_service.dart';
import '../services/doctor_session_service.dart';
import '../state/staff_state.dart';
import 'sos_responder_sheet.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_loading_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/empty_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/role_shell.dart';
import '../widgets/section_label.dart';

/// Unified emergency command center — doctor (caseload), admin & assistant
/// (platform-wide). One place to see, acknowledge, and resolve SOS events.
class StaffSosHubView extends StatefulWidget {
  const StaffSosHubView({
    super.key,
    this.initialPatientId,
    this.initialEventId,
  });

  final String? initialPatientId;
  final String? initialEventId;

  @override
  State<StaffSosHubView> createState() => _StaffSosHubViewState();
}

class _StaffSosHubViewState extends State<StaffSosHubView> {
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};
  String? _highlightEventId;
  bool _loading = true;

  /// Arriving from an alert or a patient chart scopes the hub to that patient.
  /// Held in state rather than read from the widget so it can be cleared —
  /// a responder who finishes the event they came for must land on the rest
  /// of the queue, not on an empty page that still claims work is waiting.
  String? _patientScope;

  /// Set once the operator closes an emergency, so the page states plainly
  /// what finished and offers the two honest endings: go back to where the
  /// workflow started, or stay and keep working the queue.
  ///
  /// It clears itself: a confirmation that outlives the moment it confirms
  /// stops being a confirmation and becomes furniture on the page, and this
  /// one sat on top of the queue it was reporting about.
  String? _completedFor;
  Timer? _completionTimer;

  /// How long the closing confirmation stays before standing aside.
  static const Duration _completionLinger = Duration(seconds: 9);

  /// Emergencies already closed, kept for follow-up.
  ///
  /// Not in [StaffState]: the shared queue is what still needs attention, and
  /// a closed case must never rejoin it. Fetched by the hub, for the hub.
  List<StaffPatientSos> _closed = const [];

  @override
  void initState() {
    super.initState();
    _highlightEventId = widget.initialEventId;
    _patientScope = widget.initialPatientId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refresh();
      if (mounted) setState(() => _loading = false);
      _scrollToHighlight();
    });
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Show the closing confirmation, and take it away again on its own.
  void _announceCompleted(String name) {
    _completionTimer?.cancel();
    setState(() => _completedFor = name);
    _completionTimer = Timer(_completionLinger, () {
      if (mounted) setState(() => _completedFor = null);
    });
  }

  void _dismissCompleted() {
    _completionTimer?.cancel();
    setState(() => _completedFor = null);
  }

  UserRole get _role => AuthState.instance.user?.role ?? UserRole.doctor;

  String get _currentRoute => SosNavigation.hubRouteFor(_role);

  Future<void> _refresh() async {
    if (_role == UserRole.doctor) {
      await DoctorSessionService.instance.syncFromApi();
    } else {
      await AdminSosService.instance.syncFromApi();
    }
    await _loadClosed();
    if (mounted) setState(() {});
  }

  /// The closed cases, for the follow-up section. A failure here must never
  /// take the live queue down with it — the emergencies that still need
  /// someone are the ones on screen either way.
  Future<void> _loadClosed() async {
    try {
      final all = await SosFollowUpApi.instance.fetchAll();
      if (!mounted) return;
      setState(() {
        _closed = all.where((e) => e.isClosed).toList();
      });
    } catch (_) {
      // Keep whatever follow-up list we already had.
    }
  }

  List<StaffPatientSos> _activeEvents() {
    final all = StaffState.instance.patientSos.where((e) => e.isActive).toList()
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    if (_role == UserRole.doctor) {
      final ids = StaffState.instance
          .assignedPatientsForDoctor()
          .map((p) => p.id)
          .toSet();
      return all.where((e) => ids.contains(e.patientId)).toList();
    }
    return all;
  }

  /// One card, wired to the actions the hub already owns.
  Widget _liveCard(StaffPatientSos e) => _SosEventCard(
    key: _cardKeys.putIfAbsent(e.id, GlobalKey.new),
    event: e,
    highlighted: e.id == _highlightEventId,
    showOpenChart: _role == UserRole.doctor,
    onAcknowledge: () => _resolve(e.id, 'acknowledged'),
    onResolve: () => _resolve(e.id, 'resolved'),
    onFalseAlarm: () => _resolve(e.id, 'falseAlarm'),
    onOpenChart: () => _respond(e),
    onOpenMap: e.mapsUrl != null ? () => _openMap(e.mapsUrl) : null,
  );

  /// Closed cases for the follow-up section, newest first.
  ///
  /// Prefers the server's own follow-up feed; falls back to whatever closed
  /// events the session already holds, which is what demo mode has.
  List<StaffPatientSos> _closedEvents(String? scope) {
    final source = _closed.isNotEmpty ? _closed : _recentResolvedEvents();
    final list = scope == null
        ? source
        : source.where((e) => e.patientId == scope).toList();
    return list.take(12).toList();
  }

  List<StaffPatientSos> _recentResolvedEvents() {
    final all =
        StaffState.instance.patientSos.where((e) => !e.isActive).toList()
          ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));

    if (_role == UserRole.doctor) {
      final ids = StaffState.instance
          .assignedPatientsForDoctor()
          .map((p) => p.id)
          .toSet();
      return all.where((e) => ids.contains(e.patientId)).take(8).toList();
    }
    return all.take(12).toList();
  }

  void _scrollToHighlight() {
    final id = _highlightEventId ?? widget.initialEventId;
    if (id == null) return;
    final key = _cardKeys[id];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  Future<void> _resolve(String id, String status) async {
    // Read the patient before the mutation: closing an SOS removes the event,
    // so afterwards there is nothing left to take the name from.
    final event = StaffState.instance.patientSos
        .where((e) => e.id == id)
        .firstOrNull;
    final subjectName =
        event?.patientName ??
        (event == null
            ? null
            : StaffState.instance.patientById(event.patientId)?.name) ??
        'the patient';

    final label = switch (status) {
      'acknowledged' => 'Acknowledge this SOS?',
      'resolved' => 'Mark this SOS as resolved?',
      'falseAlarm' => 'Mark as false alarm?',
      _ => 'Update this SOS?',
    };
    final message = switch (status) {
      'acknowledged' => 'The care team will see this event as acknowledged.',
      'resolved' => 'This closes the emergency event for all responders.',
      'falseAlarm' =>
        'Use only when the trigger was accidental or not an emergency.',
      _ => 'Confirm this status change.',
    };
    final ok = await AppDialog.confirm(
      context,
      title: label,
      message: message,
      danger: status == 'resolved' || status == 'falseAlarm',
      icon: AppIcons.sos,
    );
    if (ok != true || !mounted) return;

    final success = _role == UserRole.doctor
        ? await StaffState.instance.resolveSos(id, status: status)
        : await StaffState.instance.adminResolveSos(id, status: status);
    if (!mounted) return;
    if (success) {
      AppToast.success(context, 'SOS updated.');
      final closed = status == 'resolved' || status == 'falseAlarm';
      await _refresh();
      if (!mounted) return;
      if (closed) _announceCompleted(subjectName);
      // Closing the event you navigated in for leaves a scoped page with
      // nothing on it. Widen back to the full queue so the rest of the
      // waiting patients are visible instead of an empty list.
      final scope = _patientScope;
      if (scope != null && !_activeEvents().any((e) => e.patientId == scope)) {
        _clearScope();
      }
    } else {
      AppToast.error(context, 'Could not update SOS.');
    }
  }

  /// Open the responder options for one event, and honour what was chosen.
  Future<void> _respond(StaffPatientSos event) async {
    final name = event.patientName ?? 'the patient';
    final outcome = await SosResponderSheet.show(
      context,
      event: event,
      role: _role,
    );
    if (!mounted) return;
    await _refresh();
    if (!mounted) return;
    if (outcome == SosResponseOutcome.closed) {
      _announceCompleted(name);
    }
  }

  void _clearScope() {
    if (_patientScope == null) return;
    setState(() {
      _patientScope = null;
      _highlightEventId = null;
    });
  }

  void _openMap(String? url) {
    if (url == null || !kIsWeb) return;
    web_platform.openWindow(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final role = _role;
    final destinations = switch (role) {
      UserRole.doctor => StaffDestinations.doctor(),
      UserRole.mcareAssistant => StaffDestinations.assistant(),
      _ => StaffDestinations.admin(),
    };
    final profileRoute = switch (role) {
      UserRole.doctor => RouteNames.doctorProfile,
      UserRole.mcareAssistant => RouteNames.assistantProfile,
      _ => RouteNames.adminProfile,
    };
    final notificationsRoute = switch (role) {
      UserRole.doctor => RouteNames.doctorNotifications,
      UserRole.mcareAssistant => RouteNames.assistantNotifications,
      _ => RouteNames.adminNotifications,
    };

    final subtitle = switch (role) {
      UserRole.doctor => 'Active emergencies in your caseload',
      UserRole.mcareAssistant => 'Platform emergencies — respond & coordinate',
      _ => 'Platform emergencies — respond & coordinate',
    };

    return RoleShell(
      currentRoute: _currentRoute,
      destinations: destinations,
      profileRoute: profileRoute,
      notificationsRoute: notificationsRoute,
      scrollable: false,
      title: 'Emergency SOS',
      subtitle: subtitle,
      body: AnimatedBuilder(
        animation: StaffState.instance,
        builder: (context, _) {
          if (_loading) {
            return const AppLoadingView(message: 'Loading emergency events…');
          }

          final active = _activeEvents();
          final scope = _patientScope;
          final filtered = scope == null
              ? active
              : active.where((e) => e.patientId == scope).toList();
          final hiddenByScope = active.length - filtered.length;
          final waiting = filtered.where((e) => e.needsResponder).toList();
          final working = filtered.where((e) => e.isInProgress).toList();
          final closed = _closedEvents(scope);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: EdgeInsets.zero,
              children: [
                if (filtered.isNotEmpty)
                  GlassCard(
                    frosted: true,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            color: AppPalette.criticalSoft(context),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.critical,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            AppIcons.sos,
                            color: AppColors.critical,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${filtered.length} active SOS',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.critical,
                                    ),
                              ),
                              Text(
                                'Respond immediately — patients are waiting',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppPalette.textMuted(context),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_completedFor != null)
                  _CompletionBar(
                    patientName: _completedFor!,
                    remaining: active.length,
                    linger: _completionLinger,
                    returnPoint: AlertReturnPoint.current,
                    onStay: _dismissCompleted,
                    onReturn: () {
                      _dismissCompleted();
                      AlertReturnPoint.go(context);
                    },
                  ),
                if (scope != null)
                  _ScopeBanner(
                    patientName: StaffState.instance.patientById(scope)?.name,
                    hidden: hiddenByScope,
                    onShowAll: _clearScope,
                  ),
                SectionLabel(
                  title: scope == null
                      ? 'Active emergencies'
                      : 'Active emergencies · one patient',
                  icon: AppIcons.sos,
                  trailing: '${filtered.length}',
                  actionLabel: 'Refresh',
                  onAction: _refresh,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (filtered.isEmpty)
                  GlassCard(
                    frosted: true,
                    child: EmptyStateView(
                      icon: AppIcons.sos,
                      title: scope == null
                          ? 'No active SOS'
                          : 'Nothing left for this patient',
                      message: scope != null
                          ? (hiddenByScope > 0
                                ? 'This emergency is closed. '
                                      '$hiddenByScope other ${hiddenByScope == 1 ? 'patient is' : 'patients are'} '
                                      'still waiting.'
                                : 'This emergency is closed and the queue is clear.')
                          : role == UserRole.doctor
                          ? 'When a patient in your caseload triggers SOS, it appears here instantly.'
                          : 'When any patient triggers SOS, it appears here for coordination.',
                      actionLabel: scope == null ? null : 'Show all active SOS',
                      onAction: scope == null ? null : _clearScope,
                      compact: true,
                    ),
                  )
                else ...[
                  // Unowned first. These are the ones with nobody on them.
                  ...waiting.map(_liveCard),
                  // Then the ones already being worked. They are not finished
                  // — an emergency handed to a provider stays here, with what
                  // has actually happened on it, until it is closed.
                  if (working.isNotEmpty) ...[
                    if (waiting.isNotEmpty)
                      const SizedBox(height: AppSpacing.sm),
                    SectionLabel(
                      title: 'In progress — follow up',
                      icon: AppIcons.careTeam,
                      trailing: '${working.length}',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ...working.map(_liveCard),
                  ],
                ],
                if (closed.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SectionLabel(
                    title: 'Closed — how they ended',
                    icon: AppIcons.audit,
                    trailing: '${closed.length}',
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...closed.map((e) => _ResolvedSosRow(event: e, role: role)),
                ],
                const SizedBox(height: AppSpacing.huge),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResolvedSosRow extends StatelessWidget {
  const _ResolvedSosRow({required this.event, required this.role});

  final StaffPatientSos event;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final name =
        event.patientName ??
        StaffState.instance.patientById(event.patientId)?.name ??
        'Patient';
    final statusColor = switch (event.status) {
      'falseAlarm' => AppPalette.textMuted(context),
      _ => AppColors.success,
    };

    return GlassCard(
      frosted: true,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: role == UserRole.doctor
          ? () => SosNavigation.openRespond(
              context,
              patientId: event.patientId,
              eventId: event.id,
              role: role,
            )
          : null,
      child: Row(
        children: [
          Icon(AppIcons.sos, size: 16, color: statusColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${event.kindLabel} · ${DateFormat.MMMd().add_jm().format(event.triggeredAt)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // How it ended, who ended it, and how long it took. A closed
                // list that only says "resolved" cannot be followed up.
                Text(
                  [
                    event.resolutionLabel ?? event.statusLabel,
                    if (event.respondedBy != null) 'by ${event.respondedBy}',
                    if (event.respondedAt != null)
                      'in ${_elapsed(event.respondedAt!.difference(event.triggeredAt))}',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.resolutionNote != null &&
                    event.resolutionNote!.trim().isNotEmpty)
                  Text(
                    event.resolutionNote!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppPalette.textMuted(context),
                      fontSize: 10,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Text(
              event.status == 'falseAlarm' ? 'FALSE ALARM' : 'RESOLVED',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w800,
                fontSize: 9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SosEventCard extends StatelessWidget {
  const _SosEventCard({
    super.key,
    required this.event,
    required this.highlighted,
    required this.showOpenChart,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onFalseAlarm,
    required this.onOpenChart,
    this.onOpenMap,
  });

  final StaffPatientSos event;
  final bool highlighted;
  final bool showOpenChart;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;
  final VoidCallback onFalseAlarm;
  final VoidCallback onOpenChart;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name =
        event.patientName ??
        StaffState.instance.patientById(event.patientId)?.name ??
        'Patient';

    return GlassCard(
      frosted: true,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      border: highlighted
          ? Border.all(color: AppColors.critical, width: 2)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.sos, color: AppColors.critical, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _StatusPill(status: event.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            event.kindLabel,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.critical,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (event.note != null && event.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(event.note!),
            ),
          const SizedBox(height: 4),
          Text(
            '${DateFormat.MMMd().add_jm().format(event.triggeredAt)} · ${_relative(event.triggeredAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppPalette.textMuted(context),
            ),
          ),
          if (event.locationLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(
                    AppIcons.location,
                    size: 14,
                    color: AppColors.info,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      event.locationLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (event.respondedBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Responded by ${event.respondedBy}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (event.progress.isNotEmpty || event.isInProgress)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: _ProgressStrip(event: event),
            ),
          const SizedBox(height: AppSpacing.md),
          // Every responder gets this, not only doctors: an admin coordinating
          // an emergency needs the same call / locate / hand-over options.
          AppButton(
            label: 'Respond now',
            variant: AppButtonVariant.danger,
            icon: AppIcons.sos,
            expand: true,
            onPressed: onOpenChart,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (event.needsResponder) ...[
            AppButton(
              label: 'Acknowledge — en route',
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: onAcknowledge,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // How an emergency ends is only offered to whoever picked it up.
          // Closing one straight off the list meant an event could be marked
          // resolved — or a false alarm — by someone who had not called the
          // patient, read the chart, or spoken to anyone. Respond first;
          // the outcome is the end of that work, not a shortcut past it.
          Row(
            children: [
              if (onOpenMap != null)
                Expanded(
                  child: AppButton(
                    label: 'Map',
                    variant: AppButtonVariant.secondary,
                    icon: AppIcons.map,
                    onPressed: onOpenMap,
                  ),
                ),
              if (onOpenMap != null && event.isInProgress)
                const SizedBox(width: AppSpacing.sm),
              if (event.isInProgress) ...[
                Expanded(
                  child: AppButton(
                    label: 'Resolve',
                    variant: AppButtonVariant.danger,
                    onPressed: onResolve,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'False alarm',
                    variant: AppButtonVariant.secondary,
                    onPressed: onFalseAlarm,
                  ),
                ),
              ],
            ],
          ),
          if (event.needsResponder)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Respond or acknowledge before this can be closed.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How long ago, in the shortest true form. Days matter here: a follow-up
/// list that reports a three-day-old case as "72h ago" makes the reader do
/// arithmetic to find out whether it is stale.
String _relative(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// How long an emergency took from raised to closed.
String _elapsed(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) return '${d.inHours}h ${d.inMinutes % 60}m';
  return '${d.inDays}d';
}

/// What has actually happened on this emergency, without opening it.
///
/// A coordinator who hands a case to a provider used to lose sight of it: the
/// card said the emergency was acknowledged and nothing else, so "is anyone
/// actually on this?" could only be answered by opening the response sheet
/// and reading the trail. The trail already rides along with the event — this
/// puts its last line where the question gets asked.
class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.event});

  final StaffPatientSos event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = event.lastStep;
    final handedTo = event.handedTo;
    final steps = event.progress.length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(AppIcons.careTeam, size: 13, color: AppColors.info),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  handedTo != null
                      ? 'Handed to $handedTo'
                      : event.isInProgress
                      ? 'Being worked — not closed yet'
                      : 'Response in progress',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.info,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (steps > 0)
                Text(
                  '$steps step${steps == 1 ? '' : 's'}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppPalette.textMuted(context),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          if (last != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${last.label}'
                '${last.detail == null || last.detail!.trim().isEmpty ? '' : ' — ${last.detail}'}'
                ' · ${last.actorName} · ${_relative(last.at)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppPalette.textMuted(context),
                  height: 1.35,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Nothing recorded yet — nobody has opened this response.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppColors.critical,
      'acknowledged' => AppColors.warning,
      _ => AppColors.success,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Text(
        status.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 9,
        ),
      ),
    );
  }
}

/// Says out loud that the list below is showing one patient, and offers the
/// way out. Without it a scoped hub reads as "the queue is empty" while other
/// patients are still waiting — the state that made a resolved emergency look
/// like a broken page.
class _ScopeBanner extends StatelessWidget {
  const _ScopeBanner({
    required this.patientName,
    required this.hidden,
    required this.onShowAll,
  });

  final String? patientName;
  final int hidden;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.info.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(AppIcons.filter, size: 16, color: AppColors.info),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                patientName == null
                    ? 'Showing one patient only'
                    : 'Showing $patientName only',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.info,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: onShowAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.info,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
              child: Text(hidden > 0 ? 'Show all ($hidden more)' : 'Show all'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The end of an emergency workflow, stated out loud.
///
/// Closing an SOS used to leave the operator standing on whichever page the
/// flow had walked them to, with no confirmation of what had finished. This
/// names the outcome, says what is still waiting, and offers the only two
/// endings that make sense — go back to where the work started, or stay and
/// keep working the queue. It never navigates on its own.
class _CompletionBar extends StatefulWidget {
  const _CompletionBar({
    required this.patientName,
    required this.remaining,
    required this.linger,
    required this.returnPoint,
    required this.onStay,
    required this.onReturn,
  });

  final String patientName;
  final int remaining;

  /// How long the bar has before it stands aside. Drawn as a thin line so
  /// the disappearance is something the operator watched happen rather than
  /// something the page did behind their back.
  final Duration linger;
  final AlertReturnPoint? returnPoint;
  final VoidCallback onStay;
  final VoidCallback onReturn;

  @override
  State<_CompletionBar> createState() => _CompletionBarState();
}

class _CompletionBarState extends State<_CompletionBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: widget.linger,
  )..forward();

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = widget.returnPoint;
    final patientName = widget.patientName;
    final remaining = widget.remaining;
    final onStay = widget.onStay;
    final onReturn = widget.onReturn;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.success.withValues(alpha: 0.38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(AppIcons.check, size: 18, color: AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emergency closed for $patientName',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                      Text(
                        remaining == 0
                            ? 'Nothing else is waiting. Where next?'
                            : '$remaining other ${remaining == 1 ? 'emergency is' : 'emergencies are'} still waiting.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // The bar's remaining time, so it never simply vanishes.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: AnimatedBuilder(
                animation: _life,
                builder: (context, _) => LinearProgressIndicator(
                  value: 1 - _life.value,
                  minHeight: 2,
                  backgroundColor: AppColors.success.withValues(alpha: 0.15),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.success,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (target != null) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Back to ${target.label}',
                      icon: AppIcons.back,
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.sm,
                      onPressed: onReturn,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: AppButton(
                    label: remaining > 0 ? 'Keep working here' : 'Stay here',
                    icon: AppIcons.sos,
                    size: AppButtonSize.sm,
                    onPressed: onStay,
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

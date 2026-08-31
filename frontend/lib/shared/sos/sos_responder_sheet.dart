import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/api/sos_response_api.dart';
import '../../core/realtime/realtime_channel.dart';
import '../../core/realtime/realtime_refresh_mixin.dart';
import '../../core/realtime/session_poller.dart';
import '../../core/web/web_platform.dart' as web_platform;
import '../alerts/alert_center.dart';
import '../auth/auth_state.dart';
import '../models/user_role.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_dialog.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/staff_patient_profile_sheet.dart';
import 'sos_handover_sheet.dart';
import 'sos_resolution_sheet.dart';

/// What the responder chose to do, handed back to the page that opened the
/// sheet so it can decide what happens next.
enum SosResponseOutcome {
  /// The sheet was closed without closing the emergency.
  stillOpen,

  /// Ownership taken — the emergency is still live.
  acknowledged,

  /// The emergency is closed.
  closed,
}

/// "Respond now", as an actual set of things a responder can do.
///
/// Before this, responding meant taking ownership and being dropped on a list
/// — every real action (reach the patient, find them, hand the case to
/// someone, close it out) lived on a different screen, and none of them were
/// named. This gathers them in the order an emergency is actually worked:
/// reach the patient, locate them, get clinical context, escalate to a
/// provider, then close with an explicit outcome.
///
/// Every option here is wired to something real. Nothing is offered that the
/// app cannot do.
class SosResponderSheet {
  SosResponderSheet._();

  static Future<SosResponseOutcome> show(
    BuildContext context, {
    required StaffPatientSos event,
    required UserRole role,
  }) async {
    // Marking the queue as presenting silences the banner layer for as long
    // as this sheet is open. try/finally so a thrown build can never leave
    // the queue muted.
    AlertCenter.instance.beginPresenting();
    try {
      final outcome = await GlassSheet.show<SosResponseOutcome>(
        context,
        title: 'Respond to ${event.kindLabel.toLowerCase()}',
        subtitle:
            '${event.patientName ?? StaffState.instance.patientById(event.patientId)?.name ?? 'Patient'}'
            '${event.locationLabel == null ? '' : ' · ${event.locationLabel}'}',
        child: _ResponderBody(event: event, role: role),
      );
      return outcome ?? SosResponseOutcome.stillOpen;
    } finally {
      AlertCenter.instance.endPresenting();
    }
  }
}

class _ResponderBody extends StatefulWidget {
  const _ResponderBody({required this.event, required this.role});

  final StaffPatientSos event;
  final UserRole role;

  @override
  State<_ResponderBody> createState() => _ResponderBodyState();
}

class _ResponderBodyState extends State<_ResponderBody>
    with RealtimeRefreshMixin<_ResponderBody> {
  bool _busy = false;

  /// Keeps the trail current while the sheet is open on a deployment with no
  /// Reverb connection. With one, the real-time signal has already refreshed
  /// it and this tick finds nothing to do.
  Timer? _trailPoll;

  /// The recorded response trail, read from and written to the server so a
  /// handover mid-emergency — or any review afterwards — sees what was
  /// actually tried, by whom, and when.
  List<SosResponseStep> _trail = const [];
  bool _loadingTrail = true;
  String? _trailError;

  /// Always the live row, never the snapshot the sheet opened with — taking
  /// ownership has to be visible here without closing and reopening.
  StaffPatientSos get _event {
    for (final e in StaffState.instance.patientSos) {
      if (e.id == widget.event.id) return e;
    }
    return widget.event;
  }

  /// True once the emergency has left the active list — resolved or closed as
  /// a false alarm by anyone, including another responder.
  bool get _closedElsewhere =>
      !StaffState.instance.patientSos.any((e) => e.id == widget.event.id);

  String get _patientName =>
      _event.patientName ??
      StaffState.instance.patientById(_event.patientId)?.name ??
      'the patient';

  String? get _phone =>
      StaffState.instance.patientClinicalDetail(_event.patientId)?.phone;

  /// Actions are live only while the emergency is: once it is closed — by
  /// this responder or another — every control goes flat rather than
  /// silently failing against a row that no longer exists.
  bool get _live => !_busy && !_closedElsewhere;

  @override
  void initState() {
    super.initState();
    _loadTrail();
    // Two coordinators on one emergency have to see each other working it.
    // The server signals `sos` on every trail write, handover and status
    // change; the poll below covers deployments where Reverb is not up.
    watchRealtime(const {'sos', 'care'}, _refreshTrail);
    _trailPoll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (RealtimeChannel.instance.isSubscribed) return;
      unawaited(_refreshTrail());
    });
  }

  @override
  void dispose() {
    _trailPoll?.cancel();
    super.dispose();
  }

  /// Re-read the trail without re-announcing this responder. A failure is
  /// left silent: what is on screen is still the last thing the server
  /// confirmed, and an error over it would say otherwise.
  Future<void> _refreshTrail() async {
    try {
      final steps = await SosResponseApi.instance.list(widget.event.id);
      if (!mounted || steps.length == _trail.length) return;
      setState(() {
        _trail = steps;
        _trailError = null;
      });
    } catch (_) {
      // Keep what we have.
    }
  }

  Future<void> _loadTrail() async {
    try {
      // Opening a response is itself a fact worth recording: it is how a
      // second responder learns someone else is already on this.
      await SosResponseApi.instance.record(
        widget.event.id,
        action: SosResponseActions.openedResponse,
      );
      final steps = await SosResponseApi.instance.list(widget.event.id);
      if (!mounted) return;
      setState(() {
        _trail = steps;
        _loadingTrail = false;
        _trailError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingTrail = false;
        _trailError = 'Could not load the response trail.';
      });
    }
  }

  /// Append a step. Only shown once the server has taken it — a trail entry
  /// the server never accepted is worse than no entry at all, because a
  /// handover would trust it.
  Future<void> _record(String action, {String? detail}) async {
    try {
      final step = await SosResponseApi.instance.record(
        widget.event.id,
        action: action,
        detail: detail,
      );
      if (!mounted || step == null) return;
      setState(() => _trail = [..._trail, step]);
    } catch (_) {
      if (!mounted) return;
      AppToast.warn(context, 'Step taken, but not recorded on the trail.');
    }
  }

  bool _hasStep(String action) => _trail.any((s) => s.action == action);

  /// Everyone who has touched this emergency, oldest first. Derived from the
  /// trail rather than tracked separately, so it cannot drift from the record.
  List<String> get _responders {
    final seen = <String>[];
    for (final step in _trail) {
      if (step.actorName.trim().isEmpty) continue;
      if (!seen.contains(step.actorName)) seen.add(step.actorName);
    }
    return seen;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------- reach out
  Future<void> _callPatient() async {
    final phone = _phone;
    if (phone == null || phone.trim().isEmpty) {
      AppToast.warn(context, 'No phone number on file for $_patientName.');
      return;
    }
    if (kIsWeb) {
      web_platform.openWindow('tel:${phone.replaceAll(' ', '')}', '_self');
      await _record(SosResponseActions.calledPatient);
      return;
    }
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    await _record(SosResponseActions.calledPatient);
    AppToast.success(context, 'Number copied — $phone');
  }

  Future<void> _openMap() async {
    final url = _event.mapsUrl;
    if (url == null) {
      AppToast.warn(context, 'This SOS carries no GPS fix.');
      return;
    }
    if (kIsWeb) {
      web_platform.openWindow(url, '_blank');
      await _record(SosResponseActions.viewedLocation);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    await _record(SosResponseActions.viewedLocation);
    AppToast.success(context, 'Map link copied.');
  }

  Future<void> _openChart() async {
    await _record(SosResponseActions.openedChart);
    await StaffPatientProfileSheet.show(
      context,
      patientId: _event.patientId,
      patientName: _patientName,
      loadFromAdmin:
          widget.role == UserRole.admin ||
          widget.role == UserRole.mcareAssistant,
    );
  }

  Future<void> _assignProvider() => _run(() async {
    final chosen = await SosHandoverSheet.show(
      context,
      eventId: widget.event.id,
      patientName: _patientName,
    );
    if (chosen == null || !mounted) return;

    // One call does the whole handover — care-team binding, ownership, trail
    // step, and the notification that reaches the provider now rather than
    // whenever their caseload next refreshes. It is idempotent, which is what
    // makes the care team choosable at all: they are already assigned, and
    // the old path rejected exactly that as a duplicate.
    try {
      final step = await SosResponseApi.instance.handover(
        widget.event.id,
        providerId: chosen.providerId,
        detail: chosen.onCareTeam
            ? '${chosen.name} (care team)'
            : '${chosen.name} — no care-team member available',
      );
      if (!mounted) return;
      if (step != null) setState(() => _trail = [..._trail, step]);
      // Pull the stamped event back, so this sheet, the SOS list and the
      // banner layer show the new owner without being reopened.
      SessionPoller.instance.triggerNow();
      AppToast.success(context, '${chosen.name} now has this emergency.');
    } on ApiException catch (e) {
      if (!mounted) return;
      // The server knows why — a closed emergency, a missing grant, a
      // provider who went inactive. "Try again" was advice that could not
      // work for any of them.
      AppToast.error(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.error(context, 'Could not hand over — check your connection.');
    }
  });

  // -------------------------------------------------------------- outcomes
  Future<void> _acknowledge() => _run(() async {
    final ok = await StaffState.instance.updateSosForCurrentRole(
      _event.id,
      status: 'acknowledged',
    );
    if (!mounted) return;
    if (!ok) {
      AppToast.error(context, 'Could not take ownership — try again.');
      return;
    }
    await _record(SosResponseActions.tookOwnership);
    AppToast.success(context, 'You own this emergency — keep working it here.');
    // Deliberately does not close the sheet: ownership is the middle of the
    // response, not the end of it. The status line above updates and the
    // responder carries on to call, locate, hand over, or close.
  });

  Future<void> _close(String status) => _run(() async {
    String? resolution;
    String? note;

    if (status == 'resolved') {
      // Ask how it ended before ending it. "Resolved" on its own is not a
      // record anyone can review later.
      final outcome = await SosResolutionSheet.show(
        context,
        patientName: _patientName,
      );
      if (outcome == null || !mounted) return;
      resolution = outcome.resolution.apiValue;
      note = outcome.note;
    } else {
      final confirmed = await AppDialog.confirm(
        context,
        title: 'Mark as false alarm?',
        message:
            'Use this only when the trigger was accidental or not an '
            'emergency.',
        danger: true,
        icon: AppIcons.sos,
      );
      if (confirmed != true || !mounted) return;
    }

    final ok = await StaffState.instance.updateSosForCurrentRole(
      _event.id,
      status: status,
      resolution: resolution,
      resolutionNote: note,
    );
    if (!mounted) return;
    if (!ok) {
      AppToast.error(context, 'Could not update — the emergency stays open.');
      return;
    }
    Navigator.of(context).pop(SosResponseOutcome.closed);
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: StaffState.instance,
    builder: (context, _) => _buildBody(context),
  );

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    // An assistant coordinates emergencies on delegated grants, and the
    // handover needs both of them. Offering an action the server will refuse
    // is how a responder loses time in the middle of an emergency.
    final canAssign =
        (widget.role == UserRole.admin ||
            widget.role == UserRole.mcareAssistant) &&
        AuthState.instance.hasAssistantPermission(
          AssistantPermissions.canAssignPatients,
        ) &&
        AuthState.instance.hasAssistantPermission(
          AssistantPermissions.canAccessEmergencyLocation,
        );
    final phone = _phone;
    final owned = _event.status == 'acknowledged';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusTrack(
          status: _closedElsewhere ? 'closed' : _event.status,
          respondedBy: _event.respondedBy,
        ),
        if (_responders.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(AppIcons.users, size: 15, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${_responders.length} people are on this: '
                    '${_responders.join(', ')}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.info,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (_closedElsewhere)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    AppIcons.check,
                    size: 17,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'This emergency has been closed. Nothing further is '
                      'needed here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_event.note != null && _event.note!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.critical.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Text(
                _event.note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.critical,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

        _GroupLabel('Reach the patient'),
        _ResponderAction(
          icon: AppIcons.phone,
          title: kIsWeb ? 'Call $_patientName' : 'Copy phone number',
          subtitle: phone == null || phone.trim().isEmpty
              ? 'No number on file'
              : phone,
          enabled: _live && phone != null && phone.trim().isNotEmpty,
          done: _hasStep(SosResponseActions.calledPatient),
          onTap: _callPatient,
        ),
        _ResponderAction(
          icon: AppIcons.location,
          title: kIsWeb ? 'View location on map' : 'Copy map link',
          subtitle: _event.mapsUrl == null
              ? 'No GPS fix on this SOS'
              : _event.locationLabel ?? 'Live coordinates attached',
          enabled: _live && _event.mapsUrl != null,
          done: _hasStep(SosResponseActions.viewedLocation),
          onTap: _openMap,
        ),

        const SizedBox(height: AppSpacing.md),
        _GroupLabel('Get context'),
        _ResponderAction(
          icon: AppIcons.records,
          title: 'Open the patient chart',
          subtitle: 'Vitals, medications, conditions and care team',
          enabled: !_busy,
          done: _hasStep(SosResponseActions.openedChart),
          onTap: _openChart,
        ),
        if (canAssign)
          _ResponderAction(
            icon: AppIcons.assignments,
            title: 'Assign a healthworker',
            subtitle: 'Hand this patient to a provider in the care workspace',
            enabled: _live,
            done: false,
            onTap: _assignProvider,
          ),

        const SizedBox(height: AppSpacing.md),
        _GroupLabel('End this response'),
        if (!owned)
          _ResponderAction(
            icon: AppIcons.check,
            title: 'Take ownership',
            subtitle: 'Tell the care team you are on it — stays open',
            enabled: _live,
            done: false,
            accent: AppColors.warning,
            onTap: _acknowledge,
          ),
        // An outcome is the end of a response, so it is offered only to
        // whoever took the emergency on. Disabled rather than hidden: the
        // responder needs to know closing exists and what unlocks it.
        _ResponderAction(
          icon: AppIcons.checkMark,
          title: 'Resolve the emergency',
          subtitle: owned
              ? 'The patient is safe and the event is closed'
              : 'Take ownership first — then you can close this',
          enabled: _live && owned,
          done: false,
          accent: AppColors.success,
          onTap: () => _close('resolved'),
        ),
        _ResponderAction(
          icon: AppIcons.close,
          title: 'False alarm',
          subtitle: owned
              ? 'Triggered accidentally — no emergency took place'
              : 'Take ownership first — then you can close this',
          enabled: _live && owned,
          done: false,
          accent: AppColors.critical,
          onTap: () => _close('falseAlarm'),
        ),

        const SizedBox(height: AppSpacing.md),
        _GroupLabel('Response trail'),
        _TrailPanel(
          steps: _trail,
          loading: _loadingTrail,
          error: _trailError,
          onRetry: _loadTrail,
        ),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.xs,
      ),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppPalette.textMuted(context),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

/// One thing the responder can do. Disabled options state *why* rather than
/// disappearing — a responder needs to know a number is missing, not wonder
/// whether calling was ever possible.
class _ResponderAction extends StatelessWidget {
  const _ResponderAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.done,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool done;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = accent ?? Theme.of(context).colorScheme.primary;
    final fg = enabled ? tone : AppPalette.textMuted(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppPalette.surfaceAlt(context),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: enabled
                    ? tone.withValues(alpha: 0.32)
                    : AppPalette.border(context),
              ),
            ),
            child: Row(
              children: [
                Container(
                  height: 34,
                  width: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(icon, size: 17, color: fg),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: enabled
                              ? AppPalette.ink(context)
                              : AppPalette.textMuted(context),
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppPalette.textMuted(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (done)
                  const Icon(AppIcons.check, size: 17, color: AppColors.success)
                else if (enabled)
                  Icon(AppIcons.chevronRight, size: 16, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Where this emergency is in its life, so a responder can see at a glance
/// what has happened and what is left — and so a second responder arriving
/// mid-flight is not guessing.
class _StatusTrack extends StatelessWidget {
  const _StatusTrack({required this.status, this.respondedBy});

  final String status;
  final String? respondedBy;

  static const List<({String key, String label})> _steps = [
    (key: 'active', label: 'Raised'),
    (key: 'acknowledged', label: 'Owned'),
    (key: 'closed', label: 'Closed'),
  ];

  int get _reached => switch (status) {
    'active' => 0,
    'acknowledged' => 1,
    _ => 2,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    color: i <= _reached
                        ? AppColors.success
                        : AppPalette.border(context),
                  ),
                ),
              _Dot(
                label: _steps[i].label,
                done: i < _reached,
                current: i == _reached,
              ),
            ],
          ],
        ),
        if (respondedBy != null && respondedBy!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Owned by $respondedBy',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.label, required this.done, required this.current});

  final String label;
  final bool done;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final reached = done || current;
    final color = reached ? AppColors.success : AppPalette.textMuted(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 18,
          width: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done ? AppColors.success : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: current ? 2.2 : 1.4),
          ),
          child: done
              ? const Icon(AppIcons.check, size: 11, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: current ? FontWeight.w800 : FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

/// The recorded response, in the order it happened.
///
/// Read from the server rather than from this session, so a responder taking
/// over an emergency in flight sees what has already been tried instead of
/// starting again from nothing.
class _TrailPanel extends StatelessWidget {
  const _TrailPanel({
    required this.steps,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<SosResponseStep> steps;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  String _time(DateTime at) {
    final h = at.hour.toString().padLeft(2, '0');
    final m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppPalette.textMuted(context);

    Widget shell(Widget child) => Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppPalette.surfaceAlt(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: child,
    );

    if (loading) {
      return shell(
        Text(
          'Loading the response trail…',
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
      );
    }

    if (error != null) {
      return shell(
        Row(
          children: [
            Expanded(
              child: Text(
                error!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (steps.isEmpty) {
      return shell(
        Text(
          'Nothing recorded yet. Every step you take here is added, with your '
          'name and the time, so whoever picks this up next can see it.',
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
      );
    }

    return shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(
                      AppIcons.check,
                      size: 13,
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                        children: [
                          TextSpan(
                            text: step.label,
                            style: TextStyle(
                              color: AppPalette.ink(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (step.detail != null &&
                              step.detail!.trim().isNotEmpty)
                            TextSpan(text: ' — ${step.detail}'),
                          TextSpan(
                            text:
                                '\n${step.actorName} · ${_time(step.createdAt)}',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

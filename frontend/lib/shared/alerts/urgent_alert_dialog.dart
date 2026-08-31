import 'package:flutter/material.dart';

import '../../doctors/alerts/doctor_alert_resolve_sheet.dart';
import '../auth/auth_state.dart';
import '../models/user_role.dart';
import '../navigation/sos_navigation.dart';
import '../sos/sos_responder_sheet.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/patient_three_day_summary.dart';
import '../widgets/staff_patient_profile_sheet.dart';
import 'alert_center.dart';
import 'alert_return_point.dart';

/// The urgent queue, presented as a popup that can actually be worked.
///
/// The old popup only offered "Acknowledge" or "Open patient", so an admin
/// had to navigate away to do anything real and the alert was gone either
/// way. This one lets them acknowledge, fully resolve (reusing the existing
/// clinical resolution vocabulary), open the patient, or snooze — and
/// anything not attended to comes back via [AlertCenter].
class UrgentAlertDialog {
  UrgentAlertDialog._();

  /// Shows the queue if anything is due. Safe to call on every app open and
  /// on every state change — it self-suppresses while already presenting.
  static Future<void> maybeShow(BuildContext context) =>
      _present(context, AlertCenter.instance.dueNow);

  /// Opens the queue because someone asked for it.
  ///
  /// Unlike [maybeShow] this does not consult the escalation ladder — the
  /// caller has already decided these items should be worked now. Callers
  /// should pair it with [AlertCenter.forceDue] so a snooze taken inside the
  /// popup is measured from this moment.
  static Future<void> showQueue(BuildContext context, List<UrgentItem> items) =>
      _present(context, items);

  static Future<void> _present(
    BuildContext context,
    List<UrgentItem> items,
  ) async {
    final center = AlertCenter.instance;
    if (center.isPresenting) return;

    final due = items;
    if (due.isEmpty) return;

    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null || !context.mounted) return;

    center.beginPresenting();
    center.markSurfaced(due.map((i) => i.id));
    // try/finally, not a trailing call: if the dialog throws while building,
    // an un-cleared flag makes every later open a silent no-op — the queue
    // looks alive but nothing can be worked, which reads as "I cannot
    // resolve this alert".
    try {
      // SOS cannot be dismissed by tapping away; a vital warning can.
      final hasSos = due.any((i) => i.isSos);

      await showGeneralDialog<void>(
        context: navigator.context,
        barrierLabel: 'Urgent alerts',
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: hasSos ? 0.78 : 0.62),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, _, _) => _UrgentDialogBody(initial: due),
        transitionBuilder: (_, anim, _, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutBack,
          );
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );
    } finally {
      // Give whoever just worked the queue a moment with the result before
      // the layer is allowed to interrupt again. The remaining items are not
      // lost — the dashboard card and the bell still carry them.
      center.holdBanners();
      center.endPresenting();
    }
  }
}

/// Shown for the single frame between an item being handled somewhere else
/// and this dialog stepping aside. It exists so that moment reads as "someone
/// got there first" rather than as an empty box where an emergency was.
class _HandledElsewhere extends StatelessWidget {
  const _HandledElsewhere();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Material(
            color: AppPalette.surface(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    AppIcons.check,
                    size: 20,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'Handled — someone got to this one first.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UrgentDialogBody extends StatefulWidget {
  const _UrgentDialogBody({required this.initial});

  final List<UrgentItem> initial;

  @override
  State<_UrgentDialogBody> createState() => _UrgentDialogBodyState();
}

class _UrgentDialogBodyState extends State<_UrgentDialogBody> {
  late List<String> _queueIds = widget.initial.map((i) => i.id).toList();
  int _index = 0;
  bool _busy = false;

  /// Resolve the id back to a live item each build so the card always
  /// reflects current state rather than a snapshot taken when it opened.
  UrgentItem? get _current {
    if (_index >= _queueIds.length) return null;
    final id = _queueIds[_index];
    for (final item in AlertCenter.instance.openQueue) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _advance() {
    if (!mounted) return;
    // Drop anything that is no longer outstanding, then move on.
    final live = AlertCenter.instance.openQueue.map((i) => i.id).toSet();
    final currentId = _index < _queueIds.length ? _queueIds[_index] : null;
    final next = _queueIds
        .where((id) => live.contains(id) && id != currentId)
        .toList();

    // Close *before* rebuilding when nothing is left. Emptying the list first
    // and closing afterwards painted one frame of an empty dialog over a
    // dimmed barrier — the flash of "no alerts" between working one item and
    // the queue reappearing.
    if (next.isEmpty) {
      _closeSelf();
      return;
    }

    setState(() {
      _queueIds = next;
      _index = 0;
    });
  }

  /// Close **this dialog**, and only if it is still the route on top.
  ///
  /// A bare `Navigator.pop()` here was popping whatever happened to be
  /// topmost. Once this dialog had already closed — the queue empties, then a
  /// final rebuild runs — that was the page underneath, which is how an
  /// operator ended up navigating without touching anything, and on an empty
  /// window when there was nothing left to pop.
  void _closeSelf() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null || !navigator.canPop()) return;
    navigator.pop();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acknowledge(UrgentItem item) => _run(() async {
    if (item.alert != null) {
      final ok = await StaffState.instance.acknowledgeAlert(item.alert!.id);
      if (!mounted) return;
      if (!ok) {
        AppToast.error(context, 'Could not acknowledge — try again.');
        return;
      }
      AppToast.success(
        context,
        'Acknowledged. It stays on your board '
        'until resolved.',
      );
    } else if (item.sos != null) {
      final ok = await StaffState.instance.updateSosForCurrentRole(
        item.sos!.id,
        status: 'acknowledged',
      );
      if (!mounted) return;
      if (!ok) {
        AppToast.error(context, 'Could not acknowledge — try again.');
        return;
      }
      AppToast.success(context, 'Responding — patient notified.');
    }
    // Acknowledging a vital alert is the middle of the work, not the end of
    // it: it is what unlocks recording an outcome, so moving to the next item
    // here would put the outcome permanently out of reach. An SOS is
    // different — it continues in the responder workspace, not this popup.
    if (item.isSos) _advance();
  });

  Future<void> _resolve(UrgentItem item) => _run(() async {
    final alert = item.alert;
    if (alert == null) return;
    final done = await DoctorAlertResolveFlow.resolve(context, alert);
    if (!mounted) return;
    if (done) _advance();
  });

  /// Taking an SOS means owning it and entering the responder workspace. It
  /// must never silently mean "resolved"; closing an emergency stays an
  /// explicit action inside the responder flow.
  Future<void> _respondToSos(UrgentItem item) => _run(() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final pageContext = navigator.context;
    // Record where the responder was standing before anything moves them.
    AlertReturnPoint.remember(pageContext);
    navigator.pop();
    await Future<void>.delayed(Duration.zero);
    if (!pageContext.mounted) return;

    // Responding is a set of choices, not a single jump. The sheet offers
    // the real ones — reach the patient, locate them, read the chart, hand
    // the case over, close it — and reports back what was chosen.
    final outcome = await SosResponderSheet.show(
      pageContext,
      event: item.sos!,
      role: AuthState.instance.user?.role ?? UserRole.admin,
    );
    if (!pageContext.mounted) return;

    switch (outcome) {
      case SosResponseOutcome.closed:
        AlertReturnPoint.clear();
        AppToast.success(
          pageContext,
          'Emergency closed for ${item.patientName}.',
        );
      case SosResponseOutcome.acknowledged:
        // Owned but still live: the hub is where it continues to be worked.
        await SosNavigation.openRespond(
          pageContext,
          patientId: item.patientId,
          eventId: item.sos!.id,
        );
      case SosResponseOutcome.stillOpen:
        // Backed out — leave them where they were, and let the queue bring
        // the emergency back.
        AlertReturnPoint.clear();
    }
  });

  Future<void> _openPatient(UrgentItem item) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final pageContext = navigator.context;
    // Reviewing is active work, but not acknowledgement. Give the responder
    // time to inspect it; the queue brings it back if it is still ignored.
    AlertCenter.instance.snooze(item.id);
    navigator.pop();
    await Future<void>.delayed(Duration.zero);
    if (!pageContext.mounted) return;

    final role = AuthState.instance.user?.role;
    await StaffPatientProfileSheet.show(
      pageContext,
      patientId: item.patientId,
      patientName: item.patientName,
      loadFromAdmin: role == UserRole.admin || role == UserRole.mcareAssistant,
      urgentItem: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AlertCenter.instance,
      builder: (context, _) {
        final item = _current;
        if (item == null) {
          // Someone else closed this item while it was open here. Say that
          // and step aside — a dialog that blanks itself reads as the app
          // losing the alert.
          WidgetsBinding.instance.addPostFrameCallback((_) => _closeSelf());
          return const _HandledElsewhere();
        }

        final remaining = _queueIds.length - 1;
        final accent = switch (item.kind) {
          UrgentKind.sos => AppColors.critical,
          UrgentKind.criticalVital => AppColors.critical,
          UrgentKind.warningVital => AppColors.warning,
        };
        final shownTimes = AlertCenter.instance.surfaceCountFor(item.id);

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppPalette.surface(context),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                    boxShadow: [
                      BoxShadow(
                        color: AppPalette.ink(context).withValues(alpha: 0.18),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppPalette.borderStrong(context),
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusPill,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _Header(
                          item: item,
                          accent: accent,
                          remaining: remaining,
                          shownTimes: shownTimes,
                          onDefer: () {
                            AlertCenter.instance.snooze(item.id);
                            AppToast.info(
                              context,
                              'Reminding you in '
                              '${AlertCenter.defaultSnooze.inMinutes} minutes.',
                            );
                            _advance();
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _UrgentCareTeam(item: item),
                        // The summary hides itself when the patient has no
                        // verified records; take its leading spacer with it so
                        // the gap above the actions stays a single step.
                        if (PatientThreeDaySummary.hasDataFor(
                          item.patientId,
                        )) ...[
                          const SizedBox(height: AppSpacing.md),
                          PatientThreeDaySummary(
                            patientId: item.patientId,
                            highlightedVital: item.alert?.vital,
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        _Actions(
                          item: item,
                          busy: _busy,
                          onAcknowledge: () => _acknowledge(item),
                          onResolve: () =>
                              item.isSos ? _respondToSos(item) : _resolve(item),
                          onOpen: () => _openPatient(item),
                          onSnooze: () {
                            AlertCenter.instance.snooze(item.id);
                            AppToast.info(
                              context,
                              'Reminding you in '
                              '${AlertCenter.defaultSnooze.inMinutes} minutes.',
                            );
                            _advance();
                          },
                          onSkip: remaining > 0
                              ? () => setState(
                                  () =>
                                      _index = (_index + 1) % _queueIds.length,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.accent,
    required this.remaining,
    required this.shownTimes,
    required this.onDefer,
  });

  final UrgentItem item;
  final Color accent;
  final int remaining;
  final int shownTimes;
  final VoidCallback onDefer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = DateTime.now().difference(item.createdAt);
    final ageLabel = age.inMinutes < 1
        ? 'just now'
        : age.inMinutes < 60
        ? '${age.inMinutes} min ago'
        : age.inHours < 24
        ? '${age.inHours} hr ago'
        : '${age.inDays} d ago';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              alignment: Alignment.center,
              child: Icon(
                item.isSos ? AppIcons.sos : AppIcons.alert,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.isSos
                        ? 'EMERGENCY'
                        : item.kind == UrgentKind.criticalVital
                        ? 'CRITICAL'
                        : 'WARNING',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (remaining > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                child: Text(
                  '+$remaining more',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              tooltip:
                  'Remind me in ${AlertCenter.defaultSnooze.inMinutes} minutes',
              onPressed: onDefer,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: const Icon(AppIcons.close, size: 19),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppPalette.surfaceMuted(context),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.patientName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (item.detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                shownTimes > 1
                    ? 'Raised $ageLabel · still unattended after $shownTimes reminders'
                    : 'Raised $ageLabel',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: shownTimes > 1
                      ? AppColors.critical
                      : AppPalette.textMuted(context),
                  fontWeight: shownTimes > 1
                      ? FontWeight.w800
                      : FontWeight.w600,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UrgentCareTeam extends StatelessWidget {
  const _UrgentCareTeam({required this.item});

  final UrgentItem item;

  @override
  Widget build(BuildContext context) {
    final patient = StaffState.instance.patientById(item.patientId);
    final target = item.patientName.trim().toLowerCase();
    final assignments =
        StaffState.instance.assignments
            .where((entry) => entry.patient.trim().toLowerCase() == target)
            .toList()
          ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));
    final provider = assignments.isNotEmpty
        ? assignments.first.provider
        : patient?.assignedDoctor;
    final role = assignments.isNotEmpty ? assignments.first.role : 'Primary';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'CARE TEAM',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const Spacer(),
            Text(
              provider == null || provider.trim().isEmpty
                  ? 'Unassigned'
                  : '${assignments.isEmpty ? 1 : assignments.length} assigned',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.brandIndigo.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: AppColors.brandIndigo.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.brandIndigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  AppIcons.careTeam,
                  size: 16,
                  color: AppColors.brandIndigo,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider == null || provider.trim().isEmpty
                          ? 'No care provider assigned'
                          : provider,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      provider == null || provider.trim().isEmpty
                          ? 'Assign a responder from the alert workspace'
                          : '$role care',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (provider != null && provider.trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                  ),
                  child: const Text(
                    'ACTIVE',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.item,
    required this.busy,
    required this.onAcknowledge,
    required this.onResolve,
    required this.onOpen,
    required this.onSnooze,
    required this.onSkip,
  });

  final UrgentItem item;
  final bool busy;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;
  final VoidCallback onOpen;
  final VoidCallback onSnooze;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Both routes stay open. Acknowledging takes the item on without
        // closing it; resolving records the outcome and takes it on in the
        // same step — the resolve sheet demands an action and a note, and the
        // backend stamps the alert read, resolved and audited together, so
        // there is no unclaimed judgement either way. Making acknowledgement
        // a prerequisite only stranded staff who already knew the answer.
        Row(
          children: [
            if (!item.acknowledged) ...[
              Expanded(
                child: AppButton(
                  label: 'Acknowledge',
                  icon: AppIcons.check,
                  size: AppButtonSize.sm,
                  variant: item.isSos
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                  onPressed: busy ? null : onAcknowledge,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: AppButton(
                label: item.isSos ? 'Respond now' : 'Resolve',
                icon: item.isSos ? AppIcons.sos : AppIcons.checkMark,
                size: AppButtonSize.sm,
                variant: AppButtonVariant.danger,
                loading: busy,
                onPressed: onResolve,
              ),
            ),
          ],
        ),
        if (!item.isSos && !item.acknowledged)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Acknowledge to take it on, or resolve now with a reason.',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppPalette.textMuted(context),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Profile',
                icon: AppIcons.profile,
                size: AppButtonSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: busy ? null : onOpen,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: AppButton(
                label: '${AlertCenter.defaultSnooze.inMinutes}m reminder',
                icon: AppIcons.time,
                size: AppButtonSize.sm,
                variant: AppButtonVariant.ghost,
                onPressed: busy ? null : onSnooze,
              ),
            ),
            if (onSkip != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton(
                  label: 'Next',
                  icon: AppIcons.chevronRight,
                  size: AppButtonSize.sm,
                  variant: AppButtonVariant.ghost,
                  onPressed: busy ? null : onSkip,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Nothing here is dismissed permanently — anything left unattended '
          'comes back automatically.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppPalette.textMuted(context),
            fontSize: 10,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

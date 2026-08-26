import 'package:flutter/material.dart';

import '../../doctors/alerts/doctor_alert_resolve_sheet.dart';
import '../auth/auth_state.dart';
import '../models/user_role.dart';
import '../navigation/sos_navigation.dart';
import '../state/staff_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_button.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_toast.dart';
import '../widgets/staff_patient_profile_sheet.dart';
import 'alert_center.dart';

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
  static Future<void> maybeShow(BuildContext context) async {
    final center = AlertCenter.instance;
    if (center.isPresenting) return;

    final due = center.dueNow;
    if (due.isEmpty) return;

    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null || !context.mounted) return;

    center.beginPresenting();
    center.markSurfaced(due.map((i) => i.id));

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
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    center.endPresenting();
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
    setState(() {
      _queueIds = _queueIds
          .where((id) => live.contains(id) && id != currentId)
          .toList();
      _index = 0;
    });
    if (_queueIds.isEmpty && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
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
          AppToast.success(context, 'Acknowledged. It stays on your board '
              'until resolved.');
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
        _advance();
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
        if (!item.acknowledged) {
          final ok = await StaffState.instance.updateSosForCurrentRole(
            item.sos!.id,
            status: 'acknowledged',
          );
          if (!mounted) return;
          if (!ok) {
            AppToast.error(context, 'Could not take ownership — try again.');
            return;
          }
        }

        final navigator = Navigator.of(context, rootNavigator: true);
        final pageContext = navigator.context;
        navigator.pop();
        await Future<void>.delayed(Duration.zero);
        if (!pageContext.mounted) return;
        await SosNavigation.openRespond(
          pageContext,
          patientId: item.patientId,
          eventId: item.sos!.id,
        );
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
      loadFromAdmin:
          role == UserRole.admin || role == UserRole.mcareAssistant,
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
          // Everything in the batch got handled elsewhere — close cleanly.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context, rootNavigator: true).pop();
          });
          return const SizedBox.shrink();
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
                    border: Border.all(color: accent, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.4),
                        blurRadius: 34,
                        spreadRadius: 2,
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
                        _Header(
                          item: item,
                          accent: accent,
                          remaining: remaining,
                          shownTimes: shownTimes,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _Actions(
                          item: item,
                          busy: _busy,
                          onAcknowledge: () => _acknowledge(item),
                          onResolve: () => item.isSos
                              ? _respondToSos(item)
                              : _resolve(item),
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
                              ? () => setState(() =>
                                  _index = (_index + 1) % _queueIds.length)
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
  });

  final UrgentItem item;
  final Color accent;
  final int remaining;
  final int shownTimes;

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
                    item.isSos ? 'EMERGENCY' : item.kind == UrgentKind.criticalVital
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
                  fontWeight: shownTimes > 1 ? FontWeight.w800 : FontWeight.w600,
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
        AppButton(
          label: item.isSos ? 'Respond now' : 'Resolve…',
          icon: item.isSos ? AppIcons.sos : AppIcons.check,
          variant: AppButtonVariant.danger,
          expand: true,
          loading: busy,
          onPressed: onResolve,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            if (!item.acknowledged) ...[
              Expanded(
                child: AppButton(
                  label: 'Acknowledge',
                  icon: AppIcons.checkMark,
                  variant: AppButtonVariant.secondary,
                  onPressed: busy ? null : onAcknowledge,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: AppButton(
                label: 'Open patient',
                icon: AppIcons.profile,
                variant: AppButtonVariant.secondary,
                onPressed: busy ? null : onOpen,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Remind me in '
                    '${AlertCenter.defaultSnooze.inMinutes} min',
                icon: AppIcons.time,
                variant: AppButtonVariant.ghost,
                onPressed: busy ? null : onSnooze,
              ),
            ),
            if (onSkip != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Next',
                  icon: AppIcons.chevronRight,
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

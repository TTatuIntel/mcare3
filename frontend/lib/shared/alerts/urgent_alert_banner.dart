import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_icons.dart';
import '../widgets/responsive.dart';
import 'alert_center.dart';
import 'alert_return_point.dart';
import 'urgent_alert_dialog.dart';

part 'urgent_alert_banner_strip.dart';

/// The urgent queue as a stack of notifications rather than a takeover.
///
/// Staff used to be met on sign-in by a full-screen modal with a dimmed
/// barrier: it covered the page they were trying to reach, an SOS could not
/// be dismissed at all, and because the escalation ladder re-presents an
/// unattended item, the modal closed and reopened over whatever they had
/// navigated to. That is the "content disappearing and reappearing" — a
/// dialog being torn down and rebuilt, not a rendering fault.
///
/// This layer keeps the same engine ([AlertCenter]: scope, escalation ladder,
/// snooze, ringing) and changes only how it reaches the screen:
///
///   • Nothing is ever blocked. The page stays usable underneath.
///   • The whole queue arrives as one line — worst item named, the rest
///     counted — so incoming alerts cost the page a strip rather than a
///     stack of cards.
///   • Tapping it opens [UrgentAlertDialog] on the queue, where acknowledge /
///     resolve / open-patient all live.
///   • Warnings fade themselves out like a notification. Emergencies and
///     critical vitals stay put until someone actually acts on them.
///   • It stands down entirely wherever the page already renders the queue
///     itself, and for a moment after someone has just worked it.
class UrgentAlertBanners extends StatefulWidget {
  const UrgentAlertBanners({super.key, required this.child, this.currentRoute});

  final Widget child;

  /// Route currently on screen. The SOS hub and the alerts board already are
  /// the urgent queue in full, so banners are suppressed there: a floating
  /// copy of the same items is noise, and it covers the controls used to
  /// work them.
  final String? currentRoute;

  /// Routes that present the queue themselves.
  static const Set<String> queueRoutes = {
    RouteNames.doctorSos,
    RouteNames.adminSos,
    RouteNames.assistantSos,
    RouteNames.doctorAlerts,
    RouteNames.adminAlerts,
    RouteNames.assistantAlerts,
  };

  /// A warning that nobody touches steps aside on its own; an emergency
  /// never does.
  static const Duration warningLinger = Duration(seconds: 10);

  @override
  State<UrgentAlertBanners> createState() => _UrgentAlertBannersState();
}

/// Marks a subtree that already has a banner layer, so a nested mount (a
/// guided-operations hub inside a role shell) renders its child only and the
/// same alert is not stacked twice.
class _BannerScope extends InheritedWidget {
  const _BannerScope({required super.child});

  @override
  bool updateShouldNotify(_BannerScope oldWidget) => false;
}

class _UrgentAlertBannersState extends State<UrgentAlertBanners> {
  /// Ids currently on screen, in display order. Held locally rather than read
  /// from `dueNow` each build so a card keeps its position while the engine
  /// re-evaluates underneath it.
  ///
  /// Replaced wholesale, never mutated in place. Mutating it kept the same
  /// List instance, so the child stack compared equal and skipped its
  /// rebuild — leaving a card painted from the previous frame that no longer
  /// existed in state. It looked live and did nothing when tapped, which is
  /// the worst possible failure for an alert.
  List<String> _shown = const [];

  /// Per-item auto-dismiss timers for warnings.
  final Map<String, Timer> _lingerTimers = {};

  @override
  void initState() {
    super.initState();
    AlertCenter.instance.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    for (final timer in _lingerTimers.values) {
      timer.cancel();
    }
    _lingerTimers.clear();
    AlertCenter.instance.removeListener(_sync);
    super.dispose();
  }

  /// Reconcile the visible stack with the engine.
  ///
  /// Newly due items are appended and marked surfaced exactly once — marking
  /// on every rebuild would drive each item up the escalation ladder just for
  /// being looked at.
  void _sync() {
    if (!mounted) return;
    final center = AlertCenter.instance;

    // Nothing may climb the escalation ladder while the layer is down. An
    // item marked as surfaced behind a suppressed banner has been "shown" to
    // nobody, and its next real appearance would be delayed by a rung it
    // never earned.
    if (_suppressed) {
      if (_shown.isNotEmpty) {
        for (final id in _shown) {
          _cancelLinger(id);
        }
        setState(() => _shown = const []);
      }
      _removeOverlay();
      return;
    }

    final live = {for (final item in center.openQueue) item.id: item};
    final due = center.dueNow;
    final now = DateTime.now();

    // An item leaves the stack when it is attended to (gone from openQueue)
    // or deferred. Deferring has to drop it here as well as in the engine —
    // otherwise the card the user just dismissed stays on screen, since a
    // snoozed alert is still outstanding work.
    bool deferred(String id) {
      final until = center.snoozedUntilFor(id);
      return until != null && until.isAfter(now);
    }

    final next = <String>[
      for (final id in _shown)
        if (live.containsKey(id) && !deferred(id)) id,
    ];

    final fresh = <String>[];
    for (final item in due) {
      if (next.contains(item.id)) continue;
      // A page that already lists this item speaks for it. What still flies
      // is the one that lands while someone is looking at that page.
      if (!center.announcesOverInlineQueue(item)) continue;
      next.add(item.id);
      fresh.add(item.id);
    }

    // Highest severity first, then oldest first inside a severity — the order
    // someone should work them in.
    next.sort((a, b) {
      final x = live[a]!;
      final y = live[b]!;
      final byPriority = x.priority.compareTo(y.priority);
      if (byPriority != 0) return byPriority;
      return x.createdAt.compareTo(y.createdAt);
    });

    for (final id in _shown) {
      if (!next.contains(id)) _cancelLinger(id);
    }

    if (fresh.isNotEmpty) center.markSurfaced(fresh);
    for (final id in fresh) {
      final item = live[id];
      if (item != null && !item.shouldRing) _startLinger(id);
    }

    final changed =
        next.length != _shown.length ||
        List.generate(next.length, (i) => next[i] != _shown[i]).contains(true);
    if (!changed) {
      _syncOverlay();
      return;
    }

    setState(() => _shown = List.unmodifiable(next));
    _syncOverlay();
  }

  void _startLinger(String id) {
    _lingerTimers[id]?.cancel();
    _lingerTimers[id] = Timer(UrgentAlertBanners.warningLinger, () {
      if (!mounted) return;
      AlertCenter.instance.snooze(id);
    });
  }

  void _cancelLinger(String id) {
    _lingerTimers.remove(id)?.cancel();
  }

  void _dismiss(String id) {
    _cancelLinger(id);
    AlertCenter.instance.snooze(id);
  }

  Future<void> _open(List<UrgentItem> items) async {
    if (items.isEmpty) return;
    for (final item in items) {
      _cancelLinger(item.id);
    }
    // Working an alert from a banner can walk the operator to the SOS hub;
    // remember the page they were on so that flow has somewhere to end.
    AlertReturnPoint.remember(context, currentRoute: widget.currentRoute);
    // The ladder must never block someone who asked for the queue.
    AlertCenter.instance.forceDue(items.map((i) => i.id));
    await UrgentAlertDialog.showQueue(context, items);
  }

  /// The cards live in the **root overlay**, not in this page's subtree.
  ///
  /// A Stack inside the route looked equivalent and was not: while a dialog
  /// above it finishes dismissing, Flutter gates the underlying route's
  /// pointer handling, so a banner painted on screen quietly stopped
  /// accepting taps. An alert you can see and cannot act on is the worst
  /// failure this surface has, so the layer sits above routes entirely —
  /// the same place AppToast puts itself, for the same reason.
  OverlayEntry? _entry;

  /// When the whole layer must stay down.
  ///
  /// The queue's own routes are the queue in full, so a floating copy is noise
  /// that covers the controls used to work it. The hold covers the moments
  /// just after someone worked the queue, when the next item arriving as a
  /// fresh popup would cover the result of what they just did.
  ///
  /// A page that merely *lists* the queue no longer silences the layer
  /// outright — that also swallowed the alert arriving while the operator was
  /// on it. Those are filtered per item in [_sync] instead, so the standing
  /// list speaks for what it already shows and an arrival still flies.
  bool get _suppressed {
    final route = widget.currentRoute;
    if (route != null && UrgentAlertBanners.queueRoutes.contains(route)) {
      return true;
    }
    return AlertCenter.instance.bannersHeld;
  }

  void _syncOverlay() {
    if (!mounted) return;
    // While the operator is inside an alert workflow, the banners go quiet.
    // Floating a card for the very emergency being worked — on top of the
    // controls used to work it — is noise at the worst possible moment.
    if (_shown.isEmpty || _suppressed || AlertCenter.instance.isPresenting) {
      _removeOverlay();
      return;
    }
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: _BannerStack(ids: _shown, onOpen: _open, onDismiss: _dismiss),
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    // Already inside a banner layer — render the page and let the outer
    // layer own the alerts.
    if (context.dependOnInheritedWidgetOfExactType<_BannerScope>() != null) {
      return widget.child;
    }
    return _BannerScope(child: widget.child);
  }
}

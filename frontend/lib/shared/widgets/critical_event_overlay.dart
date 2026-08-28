import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts/alert_center.dart';
import '../alerts/urgent_alert_banner.dart';
import '../auth/auth_state.dart';
import '../models/user_role.dart';

/// App-wide mount point for the urgent queue.
///
/// Sits on top of [AlertCenter], which owns scope, the escalation ladder,
/// snoozing and ringing:
///
///   • On open, anything unattended in scope is due immediately.
///   • Anything left unattended returns on an escalating ladder.
///   • Critical vitals ring the device alongside SOS, and the ring stops
///     as soon as the queue is owned or the session ends.
///
/// What reaches the screen is [UrgentAlertBanners] — a stack of tappable
/// notifications that never blocks the page. It used to be a full-screen
/// modal, which covered whatever the user had just signed in to reach and,
/// because the ladder re-presents unattended items, tore itself down and
/// rebuilt over their work.
class CriticalEventOverlay extends StatefulWidget {
  const CriticalEventOverlay({
    super.key,
    required this.child,
    this.currentRoute,
  });

  final Widget child;

  /// The route being shown. The SOS hub and the alerts board *are* the urgent
  /// queue, so floating a duplicate of it over them is noise — and it sits on
  /// top of the very controls used to work the queue.
  final String? currentRoute;

  @override
  State<CriticalEventOverlay> createState() => _CriticalEventOverlayState();
}

class _CriticalEventOverlayState extends State<CriticalEventOverlay>
    with WidgetsBindingObserver {
  Timer? _poll;
  Timer? _coldOpen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deliberately not an AlertCenter listener: _maybeSurface notifies the
    // engine, so listening to it here would be a notify → listen → notify
    // loop. The banner layer is the listener; this widget only supplies the
    // clock and the lifecycle nudges the engine cannot see for itself.

    // Cold open: give the first session sync a beat to land, then surface
    // whatever is already outstanding rather than silently absorbing it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _coldOpen = Timer(const Duration(milliseconds: 900), _maybeSurface);
    });

    // Backstop for items whose escalation window elapses while the user sits
    // on a quiet screen and nothing else triggers a rebuild.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _maybeSurface());
  }

  @override
  void dispose() {
    // Both timers must be cancelled or they outlive the tree — which leaks
    // into widget tests as pending-timer failures.
    _coldOpen?.cancel();
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the app is the other moment staff expect to be caught up.
    if (state == AppLifecycleState.resumed) _maybeSurface();
  }

  bool get _isStaff {
    final role = AuthState.instance.user?.role;
    return role == UserRole.doctor ||
        role == UserRole.admin ||
        role == UserRole.mcareAssistant;
  }

  /// Nudge the engine so anything whose escalation window has elapsed is
  /// re-evaluated. The banner layer listens to [AlertCenter] and picks the
  /// items up from there — nothing is pushed on top of the user here.
  void _maybeSurface() {
    if (!mounted || !_isStaff) return;
    AlertCenter.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isStaff) return widget.child;
    return UrgentAlertBanners(
      currentRoute: widget.currentRoute,
      child: widget.child,
    );
  }
}

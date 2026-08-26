import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts/alert_center.dart';
import '../alerts/urgent_alert_dialog.dart';
import '../auth/auth_state.dart';
import '../models/user_role.dart';

/// App-wide listener that surfaces the urgent queue.
///
/// Rewritten to sit on top of [AlertCenter]. The previous version seeded
/// itself on first run and swallowed everything already outstanding, which is
/// why opening the app never showed anything, and it dropped an alert
/// permanently once dismissed. Now:
///
///   • On open, anything unattended in scope is due immediately.
///   • Anything left unattended returns on an escalating ladder.
///   • Critical vitals ring the device alongside SOS, and the ring stops
///     as soon as the queue is owned or the session ends.
class CriticalEventOverlay extends StatefulWidget {
  const CriticalEventOverlay({super.key, required this.child});
  final Widget child;

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
    AlertCenter.instance.addListener(_maybeSurface);

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
    AlertCenter.instance.removeListener(_maybeSurface);
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

  void _maybeSurface() {
    if (!mounted || !_isStaff) return;
    if (AlertCenter.instance.isPresenting) return;
    if (AlertCenter.instance.dueNow.isEmpty) return;
    UrgentAlertDialog.maybeShow(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

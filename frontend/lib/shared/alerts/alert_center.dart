import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_state.dart';
import '../models/user_role.dart';
import '../models/vital.dart';
import '../services/sos_ring_service.dart';
import '../state/staff_state.dart';

/// What kind of thing is demanding attention.
enum UrgentKind { sos, criticalVital, warningVital }

/// One item in the urgent queue, normalised across SOS events and vital
/// alerts so every surface (popup, dashboard card, badge) reads one list.
class UrgentItem {
  const UrgentItem({
    required this.id,
    required this.kind,
    required this.patientId,
    required this.patientName,
    required this.title,
    required this.detail,
    required this.createdAt,
    required this.acknowledged,
    this.alert,
    this.sos,
  });

  final String id;
  final UrgentKind kind;
  final String patientId;
  final String patientName;
  final String title;
  final String detail;
  final DateTime createdAt;

  /// True once a staff member has taken ownership. Acknowledged items stop
  /// popping but stay on the dashboard until they are actually resolved.
  final bool acknowledged;

  final StaffAlert? alert;
  final StaffPatientSos? sos;

  bool get isSos => kind == UrgentKind.sos;

  /// SOS and critical vitals ring the device; warnings do not.
  bool get shouldRing =>
      kind == UrgentKind.sos || kind == UrgentKind.criticalVital;

  int get priority => switch (kind) {
    UrgentKind.sos => 0,
    UrgentKind.criticalVital => 1,
    UrgentKind.warningVital => 2,
  };
}

/// Per-item surfacing history. Deliberately session-local: whether an item
/// has been *attended to* is backend truth (acknowledged / resolved), while
/// how often we have *shown* it is a UI concern that should reset on reload.
class _Track {
  _Track();

  DateTime? lastSurfacedAt;
  int surfaceCount = 0;
  DateTime? snoozedUntil;
}

/// The single source of truth for "what needs attention right now".
///
/// Solves three problems the old overlay had:
///   1. It seeded on first run and swallowed everything already outstanding,
///      so opening the app showed nothing. Here, anything unattended is due
///      immediately — including on a cold open.
///   2. A dismissed alert was gone forever. Here, an unattended item comes
///      back on an escalating ladder until someone actually acts on it.
///   3. Only SOS rang. Here, critical vitals ring too, and the ring stops
///      the moment the queue is attended or the session ends.
class AlertCenter extends ChangeNotifier {
  AlertCenter._() {
    StaffState.instance.addListener(_onStateChanged);
  }

  static final AlertCenter instance = AlertCenter._();

  /// Gap before an unattended item is shown again. Escalates, then holds at
  /// the final value so a stubborn alert keeps returning without spamming.
  static const List<Duration> _ladder = [
    Duration.zero,
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
  ];

  static const Duration defaultSnooze = Duration(minutes: 5);

  final Map<String, _Track> _tracks = {};
  Timer? _ticker;

  /// Set while a popup is on screen so the engine does not stack dialogs.
  bool _presenting = false;
  bool get isPresenting => _presenting;

  // The re-evaluation ticker runs only while something is watching. As a
  // singleton this would otherwise be an un-cancellable timer for the life of
  // the isolate, which leaks into widget tests as a pending timer.
  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _ticker ??= Timer.periodic(
      const Duration(seconds: 20),
      (_) => _reevaluate(),
    );
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void beginPresenting() => _presenting = true;

  void endPresenting() {
    _presenting = false;
    _reevaluate();
  }

  // ------------------------------------------------------------------
  // Queues
  // ------------------------------------------------------------------

  /// Everything unresolved in scope — what the dashboard shows. Includes
  /// acknowledged items, because acknowledging is not finishing.
  List<UrgentItem> get openQueue => _build(includeAcknowledged: true);

  /// Items that still need someone to take ownership — what may pop.
  List<UrgentItem> get popQueue => _build(includeAcknowledged: false);

  /// Unattended items whose next surfacing moment has arrived.
  List<UrgentItem> get dueNow {
    final now = DateTime.now();
    return popQueue.where((item) => _isDue(item, now)).toList();
  }

  int get openCount => openQueue.length;

  int get unattendedCount => popQueue.length;

  bool get hasSos => openQueue.any((i) => i.isSos);

  /// True when something due should be making noise, and a session is live.
  /// "Not logged out" is the gate the request asked for.
  bool get shouldRing =>
      AuthState.instance.user != null && dueNow.any((item) => item.shouldRing);

  bool _isDue(UrgentItem item, DateTime now) {
    final track = _tracks[item.id];
    if (track == null) return true; // never shown → due immediately

    final snoozed = track.snoozedUntil;
    if (snoozed != null && snoozed.isAfter(now)) return false;

    final last = track.lastSurfacedAt;
    if (last == null) return true;

    final step = _ladder[track.surfaceCount.clamp(0, _ladder.length - 1)];
    return !now.isBefore(last.add(step));
  }

  /// How many times this item has already been put in front of someone —
  /// drives the "shown Nx" escalation copy in the UI.
  int surfaceCountFor(String id) => _tracks[id]?.surfaceCount ?? 0;

  DateTime? snoozedUntilFor(String id) => _tracks[id]?.snoozedUntil;

  // ------------------------------------------------------------------
  // Mutations
  // ------------------------------------------------------------------

  /// Record that these items have just been shown, advancing their rung on
  /// the escalation ladder.
  void markSurfaced(Iterable<String> ids) {
    final now = DateTime.now();
    for (final id in ids) {
      final track = _tracks.putIfAbsent(id, _Track.new);
      track.lastSurfacedAt = now;
      track.surfaceCount++;
      track.snoozedUntil = null;
    }
    notifyListeners();
  }

  /// Explicitly defer an item. Snoozing is not attending — the item returns.
  void snooze(String id, [Duration duration = defaultSnooze]) {
    final track = _tracks.putIfAbsent(id, _Track.new);
    track.snoozedUntil = DateTime.now().add(duration);
    _syncRing();
    notifyListeners();
  }

  void snoozeAll(Iterable<String> ids, [Duration duration = defaultSnooze]) {
    for (final id in ids) {
      _tracks.putIfAbsent(id, _Track.new).snoozedUntil = DateTime.now().add(
        duration,
      );
    }
    _syncRing();
    notifyListeners();
  }

  /// Clear all local surfacing history — call on sign-out so the next user
  /// starts from a clean queue.
  void reset() {
    _tracks.clear();
    _presenting = false;
    SosRingService.instance.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    StaffState.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  // ------------------------------------------------------------------
  // internals
  // ------------------------------------------------------------------

  void _onStateChanged() => _reevaluate();

  void _reevaluate() {
    _pruneTracks();
    _syncRing();
    notifyListeners();
  }

  /// Drop history for items that are no longer outstanding, so an alert that
  /// is resolved and later re-raised starts its ladder fresh.
  void _pruneTracks() {
    if (_tracks.isEmpty) return;
    final live = openQueue.map((i) => i.id).toSet();
    _tracks.removeWhere((id, _) => !live.contains(id));
  }

  void _syncRing() {
    final ringing = SosRingService.instance.isPlaying;
    final want = shouldRing;
    if (want && !ringing) {
      SosRingService.instance.start();
    } else if (!want && ringing) {
      SosRingService.instance.stop();
    }
  }

  /// Patients this user is allowed to see. Mirrors the scope the old overlay
  /// used so no one gains visibility they did not already have.
  Set<String> _scope() {
    final user = AuthState.instance.user;
    if (user == null) return const {};
    return switch (user.role) {
      UserRole.doctor =>
        StaffState.instance
            .assignedPatientsForDoctor()
            .map((p) => p.id)
            .toSet(),
      UserRole.admin || UserRole.mcareAssistant =>
        StaffState.instance.patients.map((p) => p.id).toSet(),
      _ => const {},
    };
  }

  bool get _isStaff {
    final role = AuthState.instance.user?.role;
    return role == UserRole.doctor ||
        role == UserRole.admin ||
        role == UserRole.mcareAssistant;
  }

  List<UrgentItem> _build({required bool includeAcknowledged}) {
    if (!_isStaff) return const [];
    final scope = _scope();
    if (scope.isEmpty) return const [];

    final items = <UrgentItem>[];

    // SOS carries emergency location, so a delegated assistant only sees it
    // with the matching grant. This is what previously forced the whole
    // overlay to be admin-only; gating the item instead lets assistants
    // receive vital alerts without widening their emergency access.
    // Doctors respond to their own caseload's emergencies unconditionally —
    // hasAssistantPermission returns false for them, so check role first.
    final role = AuthState.instance.user?.role;
    final canSeeSos =
        role == UserRole.doctor ||
        role == UserRole.admin ||
        AuthState.instance.hasAssistantPermission(
          AssistantPermissions.canAccessEmergencyLocation,
        );

    for (final e in StaffState.instance.patientSos) {
      if (!canSeeSos) break;
      if (!e.isActive || !scope.contains(e.patientId)) continue;
      // An SOS that a responder has picked up is "acknowledged".
      final acked = e.status == 'acknowledged';
      if (acked && !includeAcknowledged) continue;
      final patient = StaffState.instance.patientById(e.patientId);
      items.add(
        UrgentItem(
          id: 'sos:${e.id}',
          kind: UrgentKind.sos,
          patientId: e.patientId,
          patientName: e.patientName ?? patient?.name ?? 'Patient',
          title: e.kindLabel,
          detail: [
            if (e.locationLabel != null) e.locationLabel!,
            if (e.note != null) e.note!,
          ].join(' · '),
          createdAt: e.triggeredAt,
          acknowledged: acked,
          sos: e,
        ),
      );
    }

    for (final a in StaffState.instance.alerts) {
      if (a.resolved || !scope.contains(a.patientId)) continue;
      if (a.severity != RiskLevel.critical && a.severity != RiskLevel.warning) {
        continue;
      }
      if (a.acknowledged && !includeAcknowledged) continue;
      items.add(
        UrgentItem(
          id: 'alert:${a.id}',
          kind: a.severity == RiskLevel.critical
              ? UrgentKind.criticalVital
              : UrgentKind.warningVital,
          patientId: a.patientId,
          patientName: a.patientName,
          title:
              '${a.vital.label} ${a.severity == RiskLevel.critical ? 'critical' : 'warning'}',
          detail: '${a.value} ${a.vital.unit}'.trim(),
          createdAt: a.createdAt,
          acknowledged: a.acknowledged,
          alert: a,
        ),
      );
    }

    items.sort((x, y) {
      final byPriority = x.priority.compareTo(y.priority);
      if (byPriority != 0) return byPriority;
      return y.createdAt.compareTo(x.createdAt);
    });

    return items;
  }
}

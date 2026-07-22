import 'package:flutter/foundation.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/notifications_api.dart';
import '../../core/api/staff_notification_state_api.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/notification_item.dart';
import '../models/user_role.dart';
import '../models/vital.dart';

class NotificationState extends ChangeNotifier {
  NotificationState._();
  static final NotificationState instance = NotificationState._();

  final List<AppNotification> _items = [];
  List<AppNotification> get items => List.unmodifiable(_items);

  /// Persisted read/resolve overrides for client-computed staff notifications
  /// (`staff_*` keys). Loaded from the backend so read-state survives polls and
  /// follows the user across devices, without touching clinical acknowledge
  /// state. See [loadStaffNotificationStates].
  final Map<String, ({bool read, bool resolved})> _staffStateCache = {};

  bool _isStaffKey(String id) => id.startsWith('staff_');

  /// Fetches persisted staff notification read/resolve state and re-applies it
  /// to the current inbox. Safe to call repeatedly; a network failure leaves the
  /// existing (session-local) state untouched.
  Future<void> loadStaffNotificationStates() async {
    if (!AppEnv.backendEnabled) return;
    try {
      final states = await StaffNotificationStateApi.instance.fetch();
      _staffStateCache
        ..clear()
        ..addAll(states);
      _applyStaffStateCache();
      notifyListeners();
    } catch (_) {
      // Non-blocking; keep whatever we already have.
    }
  }

  void _applyStaffStateCache() {
    if (_staffStateCache.isEmpty) return;
    for (var i = 0; i < _items.length; i++) {
      final n = _items[i];
      final s = _staffStateCache[n.id];
      if (s == null) continue;
      _items[i] = n.copyWith(
        read: n.read || s.read,
        resolved: n.resolved || s.resolved,
        resolvedAt: (n.resolved || s.resolved)
            ? (n.resolvedAt ?? DateTime.now())
            : null,
      );
    }
  }

  List<AppNotification> get activeItems =>
      _items.where((n) => !n.resolved).toList(growable: false);

  List<AppNotification> get resolvedItems =>
      _items.where((n) => n.resolved).toList(growable: false);

  List<AppNotification> resolvedVitalAlerts() =>
      resolvedItems
          .where((n) => n.kind == NotificationKind.vitalAlert)
          .toList(growable: false);

  int get unreadCount =>
      _items.where((n) => !n.read && !n.resolved).length;

  void seed(List<AppNotification> items) {
    _items
      ..clear()
      ..addAll(items);
    notifyListeners();
  }

  /// Replaces only the staff-computed notifications (IDs starting with
  /// `staff_`), leaving admin-API-backed items (`admin_notif_`) intact.
  /// Called by `StaffState._syncToNotificationCenter()` so backend
  /// notifications in the inbox survive each alert/SOS recompute cycle.
  void seedStaffComputedNotifications(List<AppNotification> items) {
    _items.removeWhere((n) => n.id.startsWith('staff_'));
    _items.addAll(items);
    _applyStaffStateCache();
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  /// Merges notifications fetched from `/admin/notifications` into the list
  /// without overwriting locally-computed staff entries. Idempotent by id.
  void mergeAdminApiNotifications(List<AppNotification> items) {
    for (final n in items) {
      final i = _items.indexWhere((e) => e.id == n.id);
      if (i == -1) {
        _items.add(n);
      } else {
        _items[i] = n;
      }
    }
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  void add(AppNotification notification) {
    _items.insert(0, notification);
    notifyListeners();
  }

  AppNotification? vitalAlertFor(VitalKey key) {
    for (final n in _items) {
      if (n.resolved || n.kind != NotificationKind.vitalAlert) continue;
      if (n.linkedVital == key) return n;
    }
    return null;
  }

  AppNotification? resolvedVitalAlertFor(VitalKey key) {
    for (final n in _items) {
      if (!n.resolved || n.kind != NotificationKind.vitalAlert) continue;
      if (n.linkedVital == key) return n;
    }
    return null;
  }

  int get resolvedVitalAlertCount =>
      _items.where((n) =>
          n.resolved &&
          n.kind == NotificationKind.vitalAlert &&
          n.linkedVital != null).length;

  /// Creates or updates a vital alert notification. Pass [alertConfig] from the
  /// matching [VitalCatalogEntry] so per-vital notification rules are respected.
  /// When [alertConfig] is null, default behaviour fires alerts for all
  /// warning/critical readings.
  void upsertVitalAlert({
    required VitalKey vital,
    required VitalReading reading,
    VitalAlertConfig? alertConfig,
  }) {
    final cfg = alertConfig ?? const VitalAlertConfig();

    // Respect per-vital notification toggles.
    if (reading.risk == RiskLevel.warning && !cfg.enableWarningAlerts) return;
    if (reading.risk == RiskLevel.critical && !cfg.enableCriticalAlerts) return;
    if (reading.risk == RiskLevel.normal || reading.risk == RiskLevel.unknown) {
      // Normal reading — auto-resolve if configured.
      if (cfg.autoResolveOnNormal) resolveVitalAlerts(vital);
      return;
    }

    final defaultTitle = switch (reading.risk) {
      RiskLevel.critical => '${vital.label} is critical',
      RiskLevel.warning => '${vital.label} is outside range',
      _ => '${vital.label} reading logged',
    };
    final title = reading.risk == RiskLevel.critical
        ? (cfg.criticalAlertTitle ?? defaultTitle)
        : (cfg.warningAlertTitle ?? defaultTitle);
    final body =
        '${reading.formatValue()} ${vital.unit} · ${_relativeStamp(reading.recordedAt)}';

    final existing = vitalAlertFor(vital);
    if (existing != null) {
      final i = _items.indexWhere((n) => n.id == existing.id);
      if (i != -1) {
        _items[i] = AppNotification(
          id: existing.id,
          kind: NotificationKind.vitalAlert,
          title: title,
          body: body,
          createdAt: reading.recordedAt,
          actionRoute: RouteNames.patientVitalDetail,
          actionArguments: vital,
        );
      }
    } else {
      add(AppNotification(
        id: 'va_${vital.name}_${DateTime.now().millisecondsSinceEpoch}',
        kind: NotificationKind.vitalAlert,
        title: title,
        body: body,
        createdAt: reading.recordedAt,
        actionRoute: RouteNames.patientVitalDetail,
        actionArguments: vital,
      ));
    }
    notifyListeners();
  }

  void resolve(String id) {
    final i = _items.indexWhere((n) => n.id == id);
    if (i == -1 || _items[i].resolved) return;
    _items[i] = _items[i].copyWith(
      resolved: true,
      resolvedAt: DateTime.now(),
      read: true,
    );
    notifyListeners();
  }

  void resolveVitalAlerts(VitalKey key) {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final n = _items[i];
      if (n.resolved || n.kind != NotificationKind.vitalAlert) continue;
      if (n.linkedVital != key) continue;
      _items[i] = n.copyWith(
        resolved: true,
        resolvedAt: DateTime.now(),
        read: true,
      );
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void markAllRead() {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].resolved) continue;
      _items[i] = _items[i].copyWith(read: true);
    }
    notifyListeners();
  }

  void markRead(String id) {
    final i = _items.indexWhere((n) => n.id == id);
    if (i == -1 || _items[i].resolved) return;
    _items[i] = _items[i].copyWith(read: true);
    notifyListeners();
  }

  /// Persisting variant of [markRead]. Routes to the correct endpoint based on
  /// the signed-in user's role.
  Future<void> markReadRemote(String id) async {
    markRead(id);
    if (!AppEnv.backendEnabled) return;
    try {
      // Client-computed staff notifications (alerts/SOS/requests/appointments)
      // have no backing row; persist their read-state separately so it is not
      // lost on the next poll.
      if (_isStaffKey(id)) {
        _staffStateCache[id] = (
          read: true,
          resolved: _staffStateCache[id]?.resolved ?? false,
        );
        await StaffNotificationStateApi.instance.setState(id, read: true);
        return;
      }
      final role = AuthState.instance.role;
      if (role == UserRole.patient) {
        await NotificationsApi.instance.markRead(id);
      } else if (role == UserRole.admin || role == UserRole.mcareAssistant) {
        await AdminApi.instance.markNotificationRead(id);
      }
    } catch (_) {
      // Non-blocking: local state already reflects the change.
    }
  }

  /// Persisting variant of [resolve]. Routes by role.
  Future<void> resolveRemote(String id) async {
    resolve(id);
    if (!AppEnv.backendEnabled) return;
    try {
      if (_isStaffKey(id)) {
        _staffStateCache[id] = (read: true, resolved: true);
        await StaffNotificationStateApi.instance.setState(id, resolved: true);
        return;
      }
      final role = AuthState.instance.role;
      if (role == UserRole.patient) {
        await NotificationsApi.instance.resolve(id);
      } else if (role == UserRole.admin || role == UserRole.mcareAssistant) {
        await AdminApi.instance.resolveNotification(id);
      }
    } catch (_) {}
  }

  /// Persisting variant of [markAllRead]. Routes by role.
  Future<void> markAllReadRemote() async {
    // Capture the staff keys that need persisting BEFORE the local mutation
    // flips their read flags (ids are stable regardless).
    final staffKeys = _items
        .where((n) => _isStaffKey(n.id) && !n.resolved)
        .map((n) => n.id)
        .toList(growable: false);
    markAllRead();
    if (!AppEnv.backendEnabled) return;
    try {
      final role = AuthState.instance.role;
      if (role == UserRole.patient) {
        await NotificationsApi.instance.markAllRead();
        return;
      }
      // Staff: persist read-state for computed items, plus any backend-backed
      // admin/assistant notifications.
      for (final k in staffKeys) {
        _staffStateCache[k] = (
          read: true,
          resolved: _staffStateCache[k]?.resolved ?? false,
        );
      }
      await StaffNotificationStateApi.instance.readAll(staffKeys);
      if (role == UserRole.admin || role == UserRole.mcareAssistant) {
        await AdminApi.instance.markAllNotificationsRead();
      }
    } catch (_) {}
  }
}

String _relativeStamp(DateTime at) {
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

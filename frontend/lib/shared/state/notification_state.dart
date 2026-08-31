import 'package:flutter/foundation.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/notifications_api.dart';
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

  bool _isStaffKey(String id) => id.startsWith('staff_');

  List<AppNotification> get activeItems =>
      _items.where((n) => !n.resolved).toList(growable: false);

  List<AppNotification> get resolvedItems =>
      _items.where((n) => n.resolved).toList(growable: false);

  List<AppNotification> resolvedVitalAlerts() => resolvedItems
      .where((n) => n.kind == NotificationKind.vitalAlert)
      .toList(growable: false);

  int get unreadCount => _items.where((n) => !n.read && !n.resolved).length;

  /// Whether the signed-in user may close a clinical alert.
  ///
  /// Clearing an alert is a clinical decision — the backend records who
  /// reviewed the reading and what they did about it — so it belongs to the
  /// care team (doctor, admin, mCare assistant). A patient dismissing their own
  /// critical vital would hide it from the people meant to act on it, and
  /// `PATCH /patient/notifications/{id}/resolve` rejects it with 403 anyway.
  bool get canClearAlerts => switch (AuthState.instance.role) {
    UserRole.doctor || UserRole.admin || UserRole.mcareAssistant => true,
    _ => false,
  };

  /// Whether [item] can be cleared by the signed-in user. Non-alert
  /// notifications stay dismissible by everyone, patients included.
  bool canResolve(AppNotification item) =>
      canClearAlerts ||
      (item.kind != NotificationKind.vitalAlert &&
          item.kind != NotificationKind.sos);

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

  /// The latest "your care team reviewed this" notice about [key].
  ///
  /// This is the message that carries who closed the alert and what they
  /// decided, so it is what the patient's screens read from when they need to
  /// show an answer in place of an alarm.
  AppNotification? resolutionNoticeFor(VitalKey key) {
    AppNotification? latest;
    for (final n in _items) {
      if (n.kind != NotificationKind.resolution) continue;
      if (n.linkedVital != key) continue;
      if (latest == null || n.createdAt.isAfter(latest.createdAt)) latest = n;
    }
    return latest;
  }

  int get resolvedVitalAlertCount => _items
      .where(
        (n) =>
            n.resolved &&
            n.kind == NotificationKind.vitalAlert &&
            n.linkedVital != null,
      )
      .length;

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
      add(
        AppNotification(
          id: 'va_${vital.name}_${DateTime.now().millisecondsSinceEpoch}',
          kind: NotificationKind.vitalAlert,
          title: title,
          body: body,
          createdAt: reading.recordedAt,
          actionRoute: RouteNames.patientVitalDetail,
          actionArguments: vital,
        ),
      );
    }
    notifyListeners();
  }

  void resolve(String id) {
    final i = _items.indexWhere((n) => n.id == id);
    if (i == -1 || _items[i].resolved) return;
    if (!canResolve(_items[i])) return;
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
      // Computed staff notifications are ephemeral presentation data. Their
      // clinical state changes only through the alert/SOS/request endpoint.
      if (_isStaffKey(id)) {
        return;
      }
      final role = AuthState.instance.role;
      if (role == UserRole.patient || role == UserRole.doctor) {
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
    final i = _items.indexWhere((n) => n.id == id);
    if (i != -1 && !canResolve(_items[i])) return;
    resolve(id);
    if (!AppEnv.backendEnabled) return;
    try {
      if (_isStaffKey(id)) {
        return;
      }
      final role = AuthState.instance.role;
      if (role == UserRole.patient || role == UserRole.doctor) {
        await NotificationsApi.instance.resolve(id);
      } else if (role == UserRole.admin || role == UserRole.mcareAssistant) {
        await AdminApi.instance.resolveNotification(id);
      }
    } catch (_) {}
  }

  /// Persisting variant of [markAllRead]. Routes by role.
  Future<void> markAllReadRemote() async {
    markAllRead();
    if (!AppEnv.backendEnabled) return;
    try {
      final role = AuthState.instance.role;
      if (role == UserRole.patient || role == UserRole.doctor) {
        await NotificationsApi.instance.markAllRead();
        return;
      }
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

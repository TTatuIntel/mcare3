import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/patient_session_sync.dart';
import '../../core/api/sos_api.dart';
import '../../core/env/app_env.dart';
import '../models/sos.dart';

class SosState extends ChangeNotifier {
  SosState._();
  static final SosState instance = SosState._();

  final List<EmergencyContact> _contacts = [];
  final List<SosEvent> _history = [];
  SosEvent? _active;

  List<EmergencyContact> get contacts => List.unmodifiable(
    _contacts..sort((a, b) => a.priority.compareTo(b.priority)),
  );
  List<SosEvent> get history => List.unmodifiable(_history);
  SosEvent? get activeEvent => _active;
  bool get hasActiveSos =>
      _active != null &&
      (_active!.status == SosStatus.active ||
          _active!.status == SosStatus.acknowledged);

  void seed({
    required List<EmergencyContact> contacts,
    required List<SosEvent> history,
  }) {
    _contacts
      ..clear()
      ..addAll(contacts);
    _history
      ..clear()
      ..addAll(history)
      ..sort((a, b) => b.triggeredAt.compareTo(a.triggeredAt));
    _active = null;
    for (final e in history) {
      if (e.status == SosStatus.active || e.status == SosStatus.acknowledged) {
        _active = e;
        break;
      }
    }
    notifyListeners();
  }

  void addContact(EmergencyContact c) {
    _contacts.add(c);
    notifyListeners();
  }

  void removeContact(String id) {
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  void updateContact(EmergencyContact c) {
    final i = _contacts.indexWhere((x) => x.id == c.id);
    if (i == -1) return;
    _contacts[i] = c;
    notifyListeners();
  }

  /// Optimistic SOS trigger — also persists via API when backend is on.
  Future<bool> triggerWithApi({
    required EmergencyKind kind,
    String? note,
    String locationLabel = 'Current location shared',
    double? latitude,
    double? longitude,
  }) async {
    if (AppEnv.backendEnabled) {
      try {
        final event = await SosApi.instance.trigger(
          kind: kind,
          note: note,
          locationLabel: locationLabel,
          latitude: latitude,
          longitude: longitude,
        );
        if (event == null) return false;
        _active = event;
        _history.insert(0, event);
        notifyListeners();
        unawaited(PatientSessionSync.instance.pullFull());
        return true;
      } catch (_) {
        return false;
      }
    }
    trigger(kind: kind, note: note, locationLabel: locationLabel);
    return true;
  }

  SosEvent trigger({
    required EmergencyKind kind,
    String? note,
    String locationLabel = 'Current location shared',
  }) {
    final event = SosEvent(
      id: 'sos_${DateTime.now().millisecondsSinceEpoch}',
      kind: kind,
      triggeredAt: DateTime.now(),
      status: SosStatus.active,
      locationLabel: locationLabel,
      note: note,
    );
    _active = event;
    _history.insert(0, event);
    notifyListeners();
    return event;
  }

  Future<bool> resolveActiveWithApi({
    SosStatus status = SosStatus.resolved,
    String? respondedBy,
  }) async {
    if (_active == null) return false;
    final current = _active!;
    if (AppEnv.backendEnabled) {
      try {
        final event = await SosApi.instance.resolve(
          current.id,
          status: status,
          respondedBy: respondedBy,
        );
        if (event == null) return false;
        final i = _history.indexWhere((e) => e.id == current.id);
        if (i != -1) _history[i] = event;
        _active =
            (status == SosStatus.active || status == SosStatus.acknowledged)
            ? event
            : null;
        notifyListeners();
        unawaited(PatientSessionSync.instance.pullFull());
        return true;
      } catch (_) {
        return false;
      }
    }
    resolveActive(status: status, respondedBy: respondedBy);
    return true;
  }

  void resolveActive({
    SosStatus status = SosStatus.resolved,
    String? respondedBy,
  }) {
    if (_active == null) return;
    final resolved = SosEvent(
      id: _active!.id,
      kind: _active!.kind,
      triggeredAt: _active!.triggeredAt,
      status: status,
      locationLabel: _active!.locationLabel,
      note: _active!.note,
      respondedBy: respondedBy ?? 'Care team',
    );
    final i = _history.indexWhere((e) => e.id == _active!.id);
    if (i != -1) _history[i] = resolved;
    _active = null;
    notifyListeners();
  }
}

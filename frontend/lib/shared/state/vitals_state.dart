import 'package:flutter/foundation.dart';

import '../../core/api/vitals_api.dart';
import '../../core/env/app_env.dart';
import '../models/vital.dart';

class VitalsState extends ChangeNotifier {
  VitalsState._();
  static final VitalsState instance = VitalsState._();

  final List<VitalReading> _readings = [];
  List<VitalReading> get all => List.unmodifiable(_readings);

  final Set<VitalKey> _tracked = {
    VitalKey.bloodPressure,
    VitalKey.heartRate,
    VitalKey.bloodOxygen,
    VitalKey.bloodGlucose,
  };
  Set<VitalKey> get tracked => Set.unmodifiable(_tracked);

  /// Vitals assigned by a doctor / admin / mCare assistant. Patients may
  /// view but not untrack these — only the assigning role can de-assign.
  final Set<VitalKey> _assigned = {
    VitalKey.bloodPressure,
    VitalKey.bloodGlucose,
  };
  Set<VitalKey> get assigned => Set.unmodifiable(_assigned);
  bool isAssigned(VitalKey k) => _assigned.contains(k);

  void seed(List<VitalReading> initial) {
    _readings
      ..clear()
      ..addAll(initial)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    notifyListeners();
  }

  /// Vitals enabled in the global catalog (admin / clinician defaults).
  final Set<VitalKey> _enabledCatalog = {};
  Set<VitalKey> get enabledCatalog => Set.unmodifiable(_enabledCatalog);

  /// Vitals the patient can choose from — catalog-enabled built-ins.
  List<VitalKey> get selectableVitals {
    if (_enabledCatalog.isEmpty) return List.unmodifiable(VitalKey.values);
    return VitalKey.values.where((v) => _enabledCatalog.contains(v)).toList();
  }

  void seedEnabledCatalog(Iterable<VitalKey> keys) {
    _enabledCatalog
      ..clear()
      ..addAll(keys);
    notifyListeners();
  }

  void seedAssigned(Iterable<VitalKey> keys) {
    _assigned
      ..clear()
      ..addAll(keys);
    _tracked.addAll(keys);
    notifyListeners();
  }

  void seedTracked(Iterable<VitalKey> keys) {
    _tracked
      ..clear()
      ..addAll(keys);
    _tracked.addAll(_assigned);
    notifyListeners();
  }

  /// Patient-facing toggle. Returns false (and no-ops) if attempting to
  /// untrack a doctor-assigned vital — that requires a clinician role.
  Future<bool> toggleTracked(VitalKey k, bool on) async {
    if (!on && _assigned.contains(k)) return false;

    final before = Set<VitalKey>.from(_tracked);
    if (on) {
      _tracked.add(k);
    } else {
      _tracked.remove(k);
    }
    notifyListeners();

    if (!AppEnv.backendEnabled) return true;

    try {
      final saved = await VitalsApi.instance.updateTracked(_tracked.toList());
      if (saved != null) {
        _tracked
          ..clear()
          ..addAll(saved);
        _tracked.addAll(_assigned);
        notifyListeners();
      }
      return true;
    } catch (_) {
      _tracked
        ..clear()
        ..addAll(before);
      notifyListeners();
      return false;
    }
  }

  /// Clinician-only mutation. Assigns or de-assigns a vital for the patient.
  /// Assigning also forces it into the tracked set.
  void setAssigned(VitalKey k, bool assigned) {
    if (assigned) {
      _assigned.add(k);
      _tracked.add(k);
    } else {
      _assigned.remove(k);
    }
    notifyListeners();
  }

  List<VitalReading> forVital(VitalKey k) =>
      _readings.where((r) => r.vital == k).toList();

  VitalReading? latestOf(VitalKey k) {
    final list = forVital(k);
    if (list.isEmpty) return null;
    return list.first;
  }

  /// Readings for tracked vitals within the last [days] days.
  List<VitalReading> recentReadings({
    int days = 7,
    Iterable<VitalKey>? vitals,
  }) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final keys = vitals ?? _tracked;
    return _readings
        .where((r) => keys.contains(r.vital) && r.recordedAt.isAfter(cutoff))
        .toList();
  }

  /// Readings inside an explicit window, newest first.
  ///
  /// [recentReadings] answers "the last N days"; a reader who has picked a
  /// calendar month or two arbitrary dates is asking a different question, and
  /// rounding it to a day count would answer a window they did not choose.
  List<VitalReading> readingsBetween(
    DateTime from,
    DateTime to, {
    Iterable<VitalKey>? vitals,
  }) {
    final keys = (vitals ?? _tracked).toSet();
    final list =
        _readings
            .where(
              (r) =>
                  keys.contains(r.vital) &&
                  !r.recordedAt.isBefore(from) &&
                  !r.recordedAt.isAfter(to),
            )
            .toList()
          ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return List.unmodifiable(list);
  }

  int readingCountInRange(VitalKey k, {int days = 7}) =>
      recentReadings(days: days, vitals: [k]).length;

  /// Optimistic add — returns immediately; caller can roll back on failure.
  void add(VitalReading r) {
    _readings.insert(0, r);
    notifyListeners();
  }

  void remove(String id) {
    _readings.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Persisting variant: POSTs to the API, then inserts the server-canonical
  /// reading. Falls back to local-only insert when the backend is disabled.
  /// Throws on API failure so the UI can show an error toast.
  Future<VitalReading> recordReading(VitalReading draft) async {
    if (!AppEnv.backendEnabled) {
      add(draft);
      return draft;
    }
    final saved = await VitalsApi.instance.record(
      vital: draft.vital,
      value: draft.value,
      secondaryValue: draft.secondaryValue,
      recordedAt: draft.recordedAt,
      note: draft.note,
    );
    final canonical = saved ?? draft;
    _readings.insert(0, canonical);
    _readings.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    notifyListeners();
    return canonical;
  }
}

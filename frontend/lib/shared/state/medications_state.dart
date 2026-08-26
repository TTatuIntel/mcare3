import 'package:flutter/foundation.dart';

import '../../core/api/medications_api.dart';
import '../../core/env/app_env.dart';
import '../models/medication.dart';

class MedicationsState extends ChangeNotifier {
  MedicationsState._();
  static final MedicationsState instance = MedicationsState._();

  final List<Medication> _medications = [];
  final List<MedicationDose> _doses = [];

  List<Medication> get all => List.unmodifiable(_medications);
  List<Medication> get active =>
      _medications.where((m) => m.active).toList(growable: false);
  List<Medication> get prescribed => active
      .where((m) => m.source == MedicationSource.doctorPrescribed)
      .toList(growable: false);
  List<Medication> get patientAdded => active
      .where((m) => m.source == MedicationSource.patientAdded)
      .toList(growable: false);
  List<MedicationDose> get doses => List.unmodifiable(_doses);

  void seed({
    required List<Medication> meds,
    required List<MedicationDose> doses,
  }) {
    _medications
      ..clear()
      ..addAll(meds);
    _doses
      ..clear()
      ..addAll(doses);
    notifyListeners();
  }

  List<MedicationDose> dosesForToday() {
    final now = DateTime.now();
    return _doses
        .where(
          (d) =>
              d.scheduledAt.year == now.year &&
              d.scheduledAt.month == now.month &&
              d.scheduledAt.day == now.day,
        )
        .toList()
      ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  Map<DosePeriod, List<MedicationDose>> dosesByPeriod() {
    final groups = <DosePeriod, List<MedicationDose>>{};
    for (final d in dosesForToday()) {
      groups.putIfAbsent(d.period, () => []).add(d);
    }
    return groups;
  }

  List<MedicationDose> dosesForMedication(String medicationId) =>
      _doses.where((d) => d.medicationId == medicationId).toList()
        ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));

  /// Recent dose activity for the meds page feed (newest first).
  List<MedicationDose> recentActivity({int limit = 6}) {
    final sorted = _doses.toList()
      ..sort((a, b) => b.scheduledAt.compareTo(a.scheduledAt));
    return sorted.take(limit).toList();
  }

  List<MedicationAlert> medicationAlerts() {
    final out = <MedicationAlert>[];
    for (final m in active) {
      final a = m.alert;
      if (a != null) out.add(a);
    }
    return out;
  }

  double adherencePercent() {
    if (_doses.isEmpty) return 0;
    final relevant = _doses
        .where((d) => d.status != DoseStatus.pending)
        .toList(growable: false);
    if (relevant.isEmpty) return 0;
    final taken = relevant.where((d) => d.status == DoseStatus.taken).length;
    return (taken / relevant.length) * 100;
  }

  void updateDose(String id, DoseStatus status) {
    final i = _doses.indexWhere((d) => d.id == id);
    if (i == -1) return;
    _doses[i] = _doses[i].copyWith(
      status: status,
      takenAt: status == DoseStatus.taken ? DateTime.now() : null,
    );
    notifyListeners();
  }

  Medication? byId(String id) {
    for (final m in _medications) {
      if (m.id == id) return m;
    }
    return null;
  }

  Medication addPatientMedication({
    required String name,
    required String dosage,
    required String frequency,
    String form = 'Tablet',
    String? instructions,
    int? refillsLeft,
    DateTime? expiryDate,
  }) {
    final med = Medication(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      dosage: dosage,
      frequency: frequency,
      form: form,
      instructions: instructions,
      prescribedBy: 'Self-reported',
      startDate: DateTime.now(),
      refillsLeft: refillsLeft,
      expiryDate: expiryDate,
      source: MedicationSource.patientAdded,
    );
    _medications.insert(0, med);
    notifyListeners();
    return med;
  }

  /// Persisting variant: POSTs to the API then inserts the server-canonical
  /// medication. Falls back to local-only when the backend is disabled.
  Future<Medication> addPatientMedicationRemote({
    required String name,
    required String dosage,
    required String frequency,
    String form = 'Tablet',
    String? instructions,
    int? refillsLeft,
    DateTime? expiryDate,
  }) async {
    final draft = Medication(
      id: 'm_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      dosage: dosage,
      frequency: frequency,
      form: form,
      instructions: instructions,
      prescribedBy: 'Self-reported',
      startDate: DateTime.now(),
      refillsLeft: refillsLeft,
      expiryDate: expiryDate,
      source: MedicationSource.patientAdded,
    );
    if (!AppEnv.backendEnabled) {
      _medications.insert(0, draft);
      notifyListeners();
      return draft;
    }
    final saved = await MedicationsApi.instance.create(draft);
    final canonical = saved ?? draft;
    _medications.insert(0, canonical);
    notifyListeners();
    return canonical;
  }

  /// Persisting variant of [updateDose]. Updates local state immediately and
  /// PATCHes the server. Rolls back on failure.
  Future<void> recordDoseRemote(String id, DoseStatus status) async {
    final i = _doses.indexWhere((d) => d.id == id);
    if (i == -1) return;
    final original = _doses[i];
    _doses[i] = original.copyWith(
      status: status,
      takenAt: status == DoseStatus.taken ? DateTime.now() : null,
    );
    notifyListeners();
    if (!AppEnv.backendEnabled) return;
    try {
      final medsById = {for (final m in _medications) m.id: m};
      final saved = await MedicationsApi.instance.recordDose(
        id,
        status,
        medsById: medsById,
      );
      if (saved != null) {
        final j = _doses.indexWhere((d) => d.id == id);
        if (j >= 0) _doses[j] = saved;
        notifyListeners();
      }
    } catch (e) {
      _doses[i] = original;
      notifyListeners();
      rethrow;
    }
  }
}

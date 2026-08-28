import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';
import '../../core/api/doctor_api.dart';
import '../../core/api/patient_profile_mapper.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../constants/route_names.dart';
import '../models/appointment.dart';
import '../models/document.dart';
import '../models/meal_plan.dart';
import '../models/notification_item.dart';
import '../models/patient_profile.dart';
import '../models/sos.dart';
import '../models/user_role.dart';
import '../models/vital.dart';
import 'notification_state.dart';
import 'staff_models.dart';

export 'staff_models.dart';

/// Fallback store for assigned-vitals notes. Kept at library scope so a
/// hot-reloaded [StaffState] singleton on web never reads an undefined field.
final Map<String, String> _staffAssignedVitalNotes = {};

// ---------------------------------------------------------------------------
// One notifier holds everything the staff side reads — patient state stays
// untouched and reused by the doctor patient-chart screen.
// ---------------------------------------------------------------------------

class StaffState extends ChangeNotifier {
  StaffState._();
  static final StaffState instance = StaffState._();

  final List<StaffPatient> _patients = [];
  final List<StaffAlert> _alerts = [];
  final List<StaffPrescription> _prescriptions = [];
  final List<StaffAppointment> _appointments = [];
  final List<ClinicalReport> _reports = [];
  final List<DirectoryUser> _users = [];
  final List<HealthworkerApproval> _approvals = [];
  final List<CareAssignment> _assignments = [];
  final List<CareRequestItem> _careRequests = [];
  final List<VitalCatalogEntry> _vitalCatalog = [];
  final List<AuditEntry> _audit = [];
  final List<SystemConfigSection> _system = [];
  final List<StaffPatientDocument> _documents = [];
  final List<StaffPatientSos> _sosEvents = [];
  final List<StaffPatientRequest> _requests = [];
  final List<StaffPatientVitalReading> _vitalReadings = [];
  final List<PatientVitalThreshold> _vitalOverrides = [];
  final List<StaffMealPlan> _mealPlans = [];
  final Map<String, Set<VitalKey>> _assignedVitalsByPatient = {};
  final Map<String, StaffPatientClinicalDetail> _clinicalDetails = {};

  List<StaffPatient> get patients => List.unmodifiable(_patients);
  List<StaffAlert> get alerts => List.unmodifiable(_alerts);
  List<StaffPrescription> get prescriptions =>
      List.unmodifiable(_prescriptions);
  List<StaffAppointment> get appointments => List.unmodifiable(_appointments);
  List<ClinicalReport> get reports => List.unmodifiable(_reports);
  List<DirectoryUser> get users => List.unmodifiable(_users);
  List<HealthworkerApproval> get approvals => List.unmodifiable(_approvals);
  List<CareAssignment> get assignments => List.unmodifiable(_assignments);
  List<CareRequestItem> get careRequests => List.unmodifiable(_careRequests);
  List<VitalCatalogEntry> get vitalCatalog => List.unmodifiable(_vitalCatalog);
  List<AuditEntry> get audit => List.unmodifiable(_audit);
  List<SystemConfigSection> get system => List.unmodifiable(_system);
  List<StaffPatientDocument> get patientDocuments =>
      List.unmodifiable(_documents);
  List<StaffPatientSos> get patientSos => List.unmodifiable(_sosEvents);
  List<StaffPatientRequest> get patientRequests => List.unmodifiable(_requests);
  List<StaffPatientVitalReading> get patientVitalReadings =>
      List.unmodifiable(_vitalReadings);

  /// Display name used in `StaffPatient.assignedDoctor` seed data.
  static String? currentDoctorDisplayName() {
    final user = AuthState.instance.user;
    if (user == null || user.role != UserRole.doctor) return null;
    return 'Dr. ${user.firstName} ${user.lastName}';
  }

  List<StaffPatient> assignedPatientsForDoctor() {
    final doc = currentDoctorDisplayName();
    if (doc == null) return List.unmodifiable(_patients);
    final matched = _patients.where((p) => p.assignedDoctor == doc).toList();
    if (matched.isNotEmpty) return matched;
    // `/doctor/session` caseload is already scoped to the signed-in doctor.
    if (AppEnv.backendEnabled && _patients.isNotEmpty) {
      return List.unmodifiable(_patients);
    }
    return matched;
  }

  /// Search text for caseload lookup (name, id, email, phone, unique id).
  bool patientMatchesQuery(StaffPatient patient, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final compactQ = q.replaceAll(RegExp(r'\s+'), '');

    bool matches(String? raw) {
      if (raw == null || raw.trim().isEmpty) return false;
      final lower = raw.toLowerCase();
      return lower.contains(q) ||
          lower.replaceAll(RegExp(r'\s+'), '').contains(compactQ);
    }

    if (matches(patient.name)) return true;
    if (matches(patient.id)) return true;

    final detail = _clinicalDetails[patient.id];
    if (matches(detail?.uniqueId)) return true;
    if (matches(detail?.email)) return true;
    if (matches(detail?.phone)) return true;

    final user = userById(patient.id);
    if (user != null) {
      if (matches(user.uniqueId)) return true;
      if (matches(user.email)) return true;
    }
    return false;
  }

  /// Compact subtitle for patient list rows.
  String patientListSubtitle(StaffPatient patient) {
    final detail = _clinicalDetails[patient.id];
    final user = userById(patient.id);
    final uniqueId = detail?.uniqueId ?? user?.uniqueId;
    final email = detail?.email ?? user?.email;
    final phone = detail?.phone;

    if (uniqueId != null && email != null) {
      return '$uniqueId · $email';
    }
    if (uniqueId != null) return uniqueId;
    if (email != null) return email;
    if (phone != null) {
      return '${patient.age} · ${patient.sex} · $phone';
    }
    return patient.demographicsLine.isNotEmpty
        ? patient.demographicsLine
        : 'Patient';
  }

  List<StaffAlert> alertsForPatient(String patientId) =>
      _alerts.where((a) => a.patientId == patientId).toList();

  List<StaffPrescription> prescriptionsForPatient(String patientId) =>
      _prescriptions.where((p) => p.patientId == patientId).toList();

  List<StaffPatientDocument> documentsForPatient(String patientId) =>
      _documents.where((d) => d.patientId == patientId).toList();

  void addDocumentForPatient(StaffPatientDocument doc) {
    _documents.insert(0, doc);
    notifyListeners();
  }

  void removeDocumentForPatient(String id) {
    _documents.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  List<StaffPatientSos> sosForPatient(String patientId) =>
      _sosEvents.where((e) => e.patientId == patientId).toList();

  List<StaffPatientRequest> requestsForPatient(String patientId) =>
      _requests.where((r) => r.patientId == patientId).toList();

  List<StaffPatientVitalReading> vitalsForPatient(String patientId) {
    final list = _vitalReadings.where((v) => v.patientId == patientId).toList();
    list.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return list;
  }

  Set<VitalKey> assignedVitalsForPatient(String patientId) => Set.unmodifiable(
    _assignedVitalsByPatient[patientId] ?? const <VitalKey>{},
  );

  String? assignedVitalsNoteForPatient(String patientId) {
    final note = _assignedVitalsNoteFor(patientId);
    if (note == null) return null;
    final trimmed = note.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _assignedVitalsNoteFor(String patientId) {
    final cached = _staffAssignedVitalNotes[patientId];
    if (cached != null) return cached;

    final detail = _clinicalDetails[patientId];
    if (detail == null) return null;

    // Dynamic read survives hot reload when detail objects predate the field.
    final dynamic raw = detail;
    final note = raw.assignedVitalsNote;
    return note is String ? note : null;
  }

  void _setAssignedVitalsNote(String patientId, String? note) {
    final trimmed = note?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _staffAssignedVitalNotes.remove(patientId);
    } else {
      _staffAssignedVitalNotes[patientId] = trimmed;
    }

    final detail = _clinicalDetails[patientId];
    if (detail == null) return;

    if (trimmed == null || trimmed.isEmpty) {
      _clinicalDetails[patientId] = detail.copyWith(
        clearAssignedVitalsNote: true,
      );
    } else {
      _clinicalDetails[patientId] = detail.copyWith(
        assignedVitalsNote: trimmed,
      );
    }
  }

  StaffPatientClinicalDetail? patientClinicalDetail(String patientId) =>
      _clinicalDetails[patientId];

  List<PatientVitalThreshold> get vitalOverrides =>
      List.unmodifiable(_vitalOverrides);

  List<PatientVitalThreshold> overridesForPatient(String patientId) =>
      _vitalOverrides.where((o) => o.patientId == patientId).toList();

  /// Effective threshold for a patient + vital: per-patient override if any,
  /// else the global catalog entry, else the product default. Single resolver
  /// every screen must use so monitoring stays consistent.
  VitalRiskRange effectiveThresholdFor(String patientId, VitalKey vital) {
    for (final o in _vitalOverrides) {
      if (o.patientId == patientId && o.vital == vital) return o.toRange();
    }
    for (final c in _vitalCatalog) {
      if (c.vital == vital) return c.toRange();
    }
    return VitalRanges.defaults[vital]!;
  }

  /// Add or replace a per-patient threshold override. Returns the new entry.
  PatientVitalThreshold upsertPatientThreshold({
    required String patientId,
    required VitalKey vital,
    required double normalMin,
    required double normalMax,
    required double warningLow,
    required double warningHigh,
    required double criticalLow,
    required double criticalHigh,
    required String setBy,
    String? note,
  }) {
    _vitalOverrides.removeWhere(
      (o) => o.patientId == patientId && o.vital == vital,
    );
    final entry = PatientVitalThreshold(
      patientId: patientId,
      vital: vital,
      normalMin: normalMin,
      normalMax: normalMax,
      warningLow: warningLow,
      warningHigh: warningHigh,
      criticalLow: criticalLow,
      criticalHigh: criticalHigh,
      setBy: setBy,
      updatedAt: DateTime.now(),
      note: note,
    );
    _vitalOverrides.add(entry);
    notifyListeners();
    return entry;
  }

  void clearPatientThreshold(String patientId, VitalKey vital) {
    final before = _vitalOverrides.length;
    _vitalOverrides.removeWhere(
      (o) => o.patientId == patientId && o.vital == vital,
    );
    if (_vitalOverrides.length != before) notifyListeners();
  }

  /// Edit a global catalog entry (used by the doctor/admin/assistant vitals
  /// hub). The default thresholds for every patient without an override
  /// follow the catalog.
  Future<void> updateCatalogEntry({
    required String id,
    required double normalMin,
    required double normalMax,
    required double warningLow,
    required double warningHigh,
    required double criticalLow,
    required double criticalHigh,
    bool? enabled,
    VitalAlertConfig? alertConfig,
    String? label,
    String? unit,
    String? description,
    String? updatedBy,
  }) async {
    VitalCatalogEntry? entry;
    double? prevNormalMin,
        prevNormalMax,
        prevWarningLow,
        prevWarningHigh,
        prevCriticalLow,
        prevCriticalHigh;
    bool? prevEnabled;
    String? prevLabel, prevUnit, prevDescription;
    VitalAlertConfig? prevAlertConfig;

    for (final c in _vitalCatalog) {
      if (c.id == id) {
        entry = c;
        prevNormalMin = c.normalMin;
        prevNormalMax = c.normalMax;
        prevWarningLow = c.warningLow;
        prevWarningHigh = c.warningHigh;
        prevCriticalLow = c.criticalLow;
        prevCriticalHigh = c.criticalHigh;
        prevEnabled = c.enabled;
        prevLabel = c.customLabel;
        prevUnit = c.customUnit;
        prevDescription = c.description;
        prevAlertConfig = c.alertConfig;

        c.normalMin = normalMin;
        c.normalMax = normalMax;
        c.warningLow = warningLow;
        c.warningHigh = warningHigh;
        c.criticalLow = criticalLow;
        c.criticalHigh = criticalHigh;
        if (enabled != null) c.enabled = enabled;
        if (alertConfig != null) c.alertConfig = alertConfig;
        if (label != null) c.customLabel = label;
        if (unit != null) c.customUnit = unit;
        if (description != null) c.description = description;
        if (updatedBy != null) c.updatedBy = updatedBy;
        c.updatedAt = DateTime.now();
        break;
      }
    }
    if (entry == null) return;
    notifyListeners();

    if (!AppEnv.backendEnabled) return;
    try {
      final body = <String, dynamic>{
        'normal_min': normalMin,
        'normal_max': normalMax,
        'warning_low': warningLow,
        'warning_high': warningHigh,
        'critical_low': criticalLow,
        'critical_high': criticalHigh,
        if (enabled != null) 'enabled': enabled,
        if (label != null) 'label': label,
        if (unit != null) 'unit': unit,
        if (description != null) 'description': description,
      };
      final raw = await _patchVitalCatalogEntry(id, body);
      if (raw != null) {
        _replaceCatalogEntry(StaffMapper.vitalCatalogEntryFromApi(raw));
      }
    } catch (_) {
      entry
        ..normalMin = prevNormalMin!
        ..normalMax = prevNormalMax!
        ..warningLow = prevWarningLow!
        ..warningHigh = prevWarningHigh!
        ..criticalLow = prevCriticalLow!
        ..criticalHigh = prevCriticalHigh!
        ..enabled = prevEnabled ?? entry.enabled
        ..customLabel = prevLabel
        ..customUnit = prevUnit
        ..description = prevDescription
        ..alertConfig = prevAlertConfig ?? entry.alertConfig;
      notifyListeners();
      rethrow;
    }
  }

  /// Create a new custom vital in the catalog. Returns the new entry.
  Future<VitalCatalogEntry> createCatalogEntry({
    required String label,
    required String unit,
    required double normalMin,
    required double normalMax,
    required double warningLow,
    required double warningHigh,
    required double criticalLow,
    required double criticalHigh,
    String? description,
    VitalAlertConfig? alertConfig,
    required String createdBy,
  }) async {
    if (AppEnv.backendEnabled) {
      try {
        final raw = await _createVitalCatalogEntryOnServer({
          'label': label,
          'unit': unit,
          'normal_min': normalMin,
          'normal_max': normalMax,
          'warning_low': warningLow,
          'warning_high': warningHigh,
          'critical_low': criticalLow,
          'critical_high': criticalHigh,
          if (description != null) 'description': description,
          'enabled': true,
        });
        if (raw != null) {
          final entry = StaffMapper.vitalCatalogEntryFromApi(raw);
          if (alertConfig != null) entry.alertConfig = alertConfig;
          _vitalCatalog.add(entry);
          notifyListeners();
          return entry;
        }
      } catch (_) {
        // Fall through to local create.
      }
    }

    final entry = VitalCatalogEntry(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      vital: null,
      normalMin: normalMin,
      normalMax: normalMax,
      warningLow: warningLow,
      warningHigh: warningHigh,
      criticalLow: criticalLow,
      criticalHigh: criticalHigh,
      enabled: true,
      customLabel: label,
      customUnit: unit,
      description: description,
      alertConfig: alertConfig,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    _vitalCatalog.add(entry);
    notifyListeners();
    return entry;
  }

  /// Remove a staff-created custom vital. Built-in VitalKey entries are
  /// protected and cannot be deleted — use [toggleVitalCatalog] to disable them.
  Future<void> removeCustomCatalogEntry(String id) async {
    final entry = _vitalCatalog.where((e) => e.id == id).firstOrNull;
    if (entry == null || !entry.isCustom) return;
    if (AppEnv.backendEnabled) {
      try {
        await _deleteVitalCatalogEntry(id);
      } catch (_) {
        return;
      }
    }
    _vitalCatalog.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  void mergeVitalCatalog(List<VitalCatalogEntry> entries) {
    if (entries.isEmpty) {
      if (AppEnv.backendEnabled) {
        _vitalCatalog.clear();
      } else if (AppEnv.demoDataEnabled && _vitalCatalog.isEmpty) {
        _seedDefaultVitalCatalog();
      }
    } else {
      _vitalCatalog
        ..clear()
        ..addAll(entries);
    }
    notifyListeners();
  }

  void _seedDefaultVitalCatalog() {
    _vitalCatalog
      ..clear()
      ..addAll(
        VitalKey.values.map((v) {
          final r = VitalRanges.defaults[v]!;
          final enabled =
              v == VitalKey.bloodPressure || v == VitalKey.bloodGlucose;
          return VitalCatalogEntry(
            id: v.name,
            vital: v,
            normalMin: r.normalMin,
            normalMax: r.normalMax,
            warningLow: r.warningLow,
            warningHigh: r.warningHigh,
            criticalLow: r.criticalLow,
            criticalHigh: r.criticalHigh,
            enabled: enabled,
            createdBy: 'system',
            createdAt: DateTime(2024),
          );
        }),
      );
  }

  List<StaffAppointment> appointmentsForPatient(String patientId) {
    final patient = patientById(patientId);
    if (patient == null) return const [];
    return _appointments
        .where((a) => a.patientId == patientId || a.patientName == patient.name)
        .toList();
  }

  StaffAppointment? appointmentById(String id) {
    for (final a in _appointments) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<StaffAppointment> appointmentsForDoctorCaseload() {
    final assignedIds = assignedPatientsForDoctor().map((p) => p.id).toSet();
    return _appointments
        .where((a) => a.patientId != null && assignedIds.contains(a.patientId))
        .toList();
  }

  Future<bool> scheduleAppointment({
    required String patientId,
    required String patientName,
    required DateTime scheduledAt,
    required AppointmentType type,
    String? reason,
    String? locationOrLink,
    int durationMinutes = 30,
    AppointmentStatus status = AppointmentStatus.scheduled,
  }) async {
    final id = 'ap_${DateTime.now().millisecondsSinceEpoch}';
    final entry = StaffAppointment(
      id: id,
      patientId: patientId,
      patientName: patientName,
      startAt: scheduledAt,
      type: type,
      reason: reason,
      status: status,
      durationMinutes: durationMinutes,
      locationOrLink:
          locationOrLink ??
          (type == AppointmentType.virtual
              ? 'https://meet.mcare.app/$id'
              : null),
    );

    _appointments.add(entry);
    notifyListeners();

    if (!AppEnv.backendEnabled) return true;

    try {
      final res = await DoctorApi.instance.scheduleAppointment(
        patientUserId: patientId,
        scheduledAt: scheduledAt,
        durationMinutes: durationMinutes,
        type: _apiType(type),
        reason: reason,
        locationOrLink: entry.locationOrLink,
      );
      if (res != null && res['id'] != null) {
        final idx = _appointments.indexWhere((a) => a.id == id);
        if (idx >= 0) {
          _appointments[idx] = StaffMapper.appointmentFromApi(res);
          notifyListeners();
        }
      }
      return true;
    } catch (_) {
      _appointments.removeWhere((a) => a.id == id);
      notifyListeners();
      return false;
    }
  }

  Future<bool> confirmAppointment(String id) =>
      _updateAppointmentStatus(id, AppointmentStatus.confirmed);

  Future<bool> completeAppointment(String id) =>
      _updateAppointmentStatus(id, AppointmentStatus.completed);

  Future<bool> cancelAppointment(String id, {String? reason}) async {
    final i = _appointments.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    final before = _appointments[i];
    _appointments[i] = before.copyWith(
      status: AppointmentStatus.cancelled,
      cancellationReason: reason,
    );
    notifyListeners();

    if (!AppEnv.backendEnabled) return true;

    try {
      await DoctorApi.instance.updateAppointment(
        id,
        status: 'cancelled',
        cancellationReason: reason,
      );
      return true;
    } catch (_) {
      _appointments[i] = before;
      notifyListeners();
      return false;
    }
  }

  Future<bool> rescheduleAppointment(String id, DateTime newTime) async {
    final i = _appointments.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    final before = _appointments[i];
    _appointments[i] = before.copyWith(
      startAt: newTime,
      status: AppointmentStatus.scheduled,
    );
    notifyListeners();

    if (!AppEnv.backendEnabled) return true;

    try {
      await DoctorApi.instance.updateAppointment(
        id,
        scheduledAt: newTime,
        status: 'scheduled',
      );
      return true;
    } catch (_) {
      _appointments[i] = before;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _updateAppointmentStatus(
    String id,
    AppointmentStatus status,
  ) async {
    final i = _appointments.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    final before = _appointments[i];
    _appointments[i] = before.copyWith(status: status);
    notifyListeners();

    if (!AppEnv.backendEnabled) return true;

    try {
      await DoctorApi.instance.updateAppointment(id, status: status.name);
      return true;
    } catch (_) {
      _appointments[i] = before;
      notifyListeners();
      return false;
    }
  }

  static String _apiType(AppointmentType type) => switch (type) {
    AppointmentType.inPerson => 'inPerson',
    AppointmentType.virtual => 'virtual',
    AppointmentType.phone => 'phone',
  };

  List<ClinicalReport> reportsForPatient(String patientId) {
    final patient = patientById(patientId);
    if (patient == null) return const [];
    return _reports.where((r) => r.patientName == patient.name).toList();
  }

  int openAlertCountForPatient(String patientId) => alertsForPatient(
    patientId,
  ).where((a) => !a.acknowledged && !a.resolved).length;

  List<StaffMealPlan> mealPlansForPatient(String patientId) =>
      _mealPlans.where((m) => m.patientId == patientId).toList();

  Future<bool> addMealPlan(StaffMealPlan plan) {
    _mealPlans.insert(0, plan);
    notifyListeners();
    if (!AppEnv.backendEnabled) return Future.value(true);
    return DoctorApi.instance
        .assignMealPlan(
          patientUserId: plan.patientId,
          title: plan.title,
          mealType: plan.mealType.name,
          description: plan.description,
          calories: plan.calories,
          protein: plan.protein,
          carbs: plan.carbs,
          fat: plan.fat,
          notes: plan.notes,
        )
        .then((data) {
          if (data != null) {
            final raw = (data['meal_plan'] as Map?)?.cast<String, dynamic>();
            if (raw != null) {
              raw['patient_id'] ??= plan.patientId;
              raw['patient_name'] ??= plan.patientName;
              final i = _mealPlans.indexWhere((m) => m.id == plan.id);
              if (i != -1) {
                _mealPlans[i] = StaffMapper.mealPlanFromApi(raw);
                notifyListeners();
              }
            }
          }
          return true;
        })
        .catchError((_) {
          _mealPlans.removeWhere((m) => m.id == plan.id);
          notifyListeners();
          return false;
        });
  }

  Future<bool> removeMealPlan(String id) {
    StaffMealPlan? before;
    for (final m in _mealPlans) {
      if (m.id == id) {
        before = m;
        break;
      }
    }
    if (before == null) return Future.value(false);
    return _doctorMutation(
      apply: () => _mealPlans.removeWhere((m) => m.id == id),
      revert: () => _mealPlans.add(before!),
      apiCall: () => DoctorApi.instance.removeMealPlan(id),
    );
  }

  bool hasActiveSos(String patientId) =>
      sosForPatient(patientId).any((e) => e.isActive);

  StaffPatient? patientById(String id) {
    for (final p in _patients) {
      if (p.id == id) return p;
    }
    return null;
  }

  ClinicalReport? reportById(String id) {
    for (final r in _reports) {
      if (r.id == id) return r;
    }
    return null;
  }

  DirectoryUser? userById(String id) {
    for (final u in _users) {
      if (u.id == id) return u;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Seed (mock) — called by mock_bootstrap or directly from auth_service when
  // signing in as a staff role.
  // -------------------------------------------------------------------------
  void seedDemo() {
    final now = DateTime.now();
    _patients
      ..clear()
      ..addAll([
        StaffPatient(
          id: 'p_001',
          name: 'Amara Okonkwo',
          age: 54,
          sex: 'F',
          condition: 'Type 2 Diabetes · Hypertension',
          risk: RiskLevel.warning,
          lastReading: now.subtract(const Duration(minutes: 18)),
          assignedDoctor: 'Dr. Kojo Mensah',
          unreadAlerts: 2,
        ),
        StaffPatient(
          id: 'p_002',
          name: 'Brian Otieno',
          age: 41,
          sex: 'M',
          condition: 'Asthma',
          risk: RiskLevel.normal,
          lastReading: now.subtract(const Duration(hours: 2)),
          assignedDoctor: 'Dr. Kojo Mensah',
        ),
        StaffPatient(
          id: 'p_003',
          name: 'Wangari Njeri',
          age: 67,
          sex: 'F',
          condition: 'Post-stroke recovery',
          risk: RiskLevel.critical,
          lastReading: now.subtract(const Duration(minutes: 4)),
          assignedDoctor: 'Dr. Sarah Adeyemi',
          unreadAlerts: 3,
        ),
        StaffPatient(
          id: 'p_004',
          name: 'Daniel Mwangi',
          age: 33,
          sex: 'M',
          condition: 'Routine wellness',
          risk: RiskLevel.normal,
          lastReading: now.subtract(const Duration(hours: 14)),
          assignedDoctor: 'Dr. Kojo Mensah',
        ),
        StaffPatient(
          id: 'p_005',
          name: 'Esther Wambui',
          age: 60,
          sex: 'F',
          condition: 'Hypertension',
          risk: RiskLevel.warning,
          lastReading: now.subtract(const Duration(hours: 1)),
          assignedDoctor: 'Dr. Kojo Mensah',
          unreadAlerts: 1,
        ),
      ]);

    _alerts
      ..clear()
      ..addAll([
        StaffAlert(
          id: 'al_1',
          patientId: 'p_003',
          patientName: 'Wangari Njeri',
          vital: VitalKey.bloodPressure,
          value: '172/108 mmHg',
          severity: RiskLevel.critical,
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
        StaffAlert(
          id: 'al_2',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          vital: VitalKey.bloodGlucose,
          value: '168 mg/dL',
          severity: RiskLevel.warning,
          createdAt: now.subtract(const Duration(minutes: 22)),
        ),
        StaffAlert(
          id: 'al_3',
          patientId: 'p_005',
          patientName: 'Esther Wambui',
          vital: VitalKey.heartRate,
          value: '112 bpm',
          severity: RiskLevel.warning,
          createdAt: now.subtract(const Duration(hours: 1, minutes: 4)),
        ),
        StaffAlert(
          id: 'al_4',
          patientId: 'p_003',
          patientName: 'Wangari Njeri',
          vital: VitalKey.bloodOxygen,
          value: '88 %',
          severity: RiskLevel.critical,
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
      ]);

    _prescriptions
      ..clear()
      ..addAll([
        StaffPrescription(
          id: 'rx_1',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          drug: 'Metformin',
          dosage: '500 mg',
          frequency: 'Twice daily',
          duration: '90 days',
          issuedAt: now.subtract(const Duration(days: 30)),
        ),
        StaffPrescription(
          id: 'rx_2',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          drug: 'Lisinopril',
          dosage: '10 mg',
          frequency: 'Once daily',
          duration: '60 days',
          issuedAt: now.subtract(const Duration(days: 15)),
        ),
        StaffPrescription(
          id: 'rx_3',
          patientId: 'p_005',
          patientName: 'Esther Wambui',
          drug: 'Amlodipine',
          dosage: '5 mg',
          frequency: 'Once daily',
          duration: '30 days',
          issuedAt: now.subtract(const Duration(days: 2)),
        ),
      ]);

    _appointments
      ..clear()
      ..addAll([
        StaffAppointment(
          id: 'ap_1',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          startAt: now.add(const Duration(days: 1, hours: 3)),
          type: AppointmentType.virtual,
          status: AppointmentStatus.confirmed,
          reason: 'Quarterly diabetes review',
          locationOrLink: 'https://meet.mcare.app/ap_1',
        ),
        StaffAppointment(
          id: 'ap_2',
          patientId: 'p_002',
          patientName: 'Brian Otieno',
          startAt: now.add(const Duration(hours: 5)),
          type: AppointmentType.inPerson,
          status: AppointmentStatus.scheduled,
          reason: 'Asthma follow-up',
          locationOrLink: 'mCare Clinic, Room 2A',
        ),
        StaffAppointment(
          id: 'ap_3',
          patientId: 'p_005',
          patientName: 'Esther Wambui',
          startAt: now.add(const Duration(days: 1, hours: 1)),
          type: AppointmentType.phone,
          status: AppointmentStatus.scheduled,
          reason: 'Medication check-in',
        ),
        StaffAppointment(
          id: 'ap_4',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          startAt: now.subtract(const Duration(days: 10)),
          type: AppointmentType.virtual,
          status: AppointmentStatus.completed,
          reason: 'HbA1c review',
        ),
      ]);

    _documents
      ..clear()
      ..addAll([
        StaffPatientDocument(
          id: 'doc_1',
          patientId: 'p_001',
          title: 'HbA1c lab result',
          category: 'Lab result',
          uploadedAt: now.subtract(const Duration(days: 3)),
        ),
        StaffPatientDocument(
          id: 'doc_2',
          patientId: 'p_001',
          title: 'Eye exam imaging',
          category: 'Imaging',
          fileType: DocumentFileType.image,
          uploadedAt: now.subtract(const Duration(days: 10)),
        ),
        StaffPatientDocument(
          id: 'doc_3',
          patientId: 'p_003',
          title: 'Discharge summary',
          category: 'Discharge',
          uploadedAt: now.subtract(const Duration(days: 1)),
        ),
      ]);

    _sosEvents
      ..clear()
      ..addAll([
        StaffPatientSos(
          id: 'sos_1',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          kind: 'medical',
          status: 'active',
          triggeredAt: now.subtract(const Duration(minutes: 12)),
          locationLabel: 'Nairobi, Westlands',
          note: 'Patient reports chest tightness.',
          latitude: -1.2674,
          longitude: 36.8070,
        ),
        StaffPatientSos(
          id: 'sos_0',
          patientId: 'p_005',
          patientName: 'Esther Wambui',
          kind: 'fall',
          status: 'resolved',
          triggeredAt: now.subtract(const Duration(days: 2)),
          locationLabel: 'Nairobi, Kilimani',
          respondedBy: 'Dr. Kojo Mensah',
        ),
      ]);

    _requests
      ..clear()
      ..addAll([
        StaffPatientRequest(
          id: 'req_1',
          patientId: 'p_001',
          type: 'Vital report',
          summary: '30-day glucose & BP summary',
          status: 'pending',
          createdAt: now.subtract(const Duration(hours: 6)),
        ),
        StaffPatientRequest(
          id: 'req_2',
          patientId: 'p_005',
          type: 'Consultation',
          summary: 'Medication side-effect review',
          status: 'pending',
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ]);

    _vitalReadings
      ..clear()
      ..addAll([
        StaffPatientVitalReading(
          patientId: 'p_001',
          vital: VitalKey.heartRate,
          value: '70 bpm',
          risk: RiskLevel.normal,
          recordedAt: now.subtract(const Duration(hours: 9)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_001',
          vital: VitalKey.bloodGlucose,
          value: '95 mg/dL',
          risk: RiskLevel.critical,
          recordedAt: now.subtract(const Duration(hours: 6)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_004',
          vital: VitalKey.weight,
          value: '78.0 kg',
          risk: RiskLevel.normal,
          recordedAt: now.subtract(const Duration(hours: 14)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_001',
          vital: VitalKey.bloodPressure,
          value: '128/73 mmHg',
          risk: RiskLevel.warning,
          recordedAt: now.subtract(const Duration(hours: 3)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_002',
          vital: VitalKey.bloodOxygen,
          value: '95%',
          risk: RiskLevel.normal,
          recordedAt: now.subtract(const Duration(hours: 2)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_001',
          vital: VitalKey.bloodGlucose,
          value: '168 mg/dL',
          risk: RiskLevel.warning,
          recordedAt: now.subtract(const Duration(minutes: 22)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_003',
          vital: VitalKey.bloodPressure,
          value: '172/108 mmHg',
          risk: RiskLevel.critical,
          recordedAt: now.subtract(const Duration(minutes: 5)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_003',
          vital: VitalKey.bloodOxygen,
          value: '88 %',
          risk: RiskLevel.critical,
          recordedAt: now.subtract(const Duration(hours: 2)),
        ),
        StaffPatientVitalReading(
          patientId: 'p_005',
          vital: VitalKey.heartRate,
          value: '112 bpm',
          risk: RiskLevel.warning,
          recordedAt: now.subtract(const Duration(hours: 1)),
        ),
      ]);

    _assignedVitalsByPatient
      ..clear()
      ..addAll({
        'p_001': {VitalKey.bloodPressure, VitalKey.bloodGlucose},
        'p_003': {
          VitalKey.bloodPressure,
          VitalKey.heartRate,
          VitalKey.bloodOxygen,
        },
        'p_005': {VitalKey.bloodPressure, VitalKey.heartRate},
      });
    _staffAssignedVitalNotes
      ..clear()
      ..addAll({
        'p_001': 'Track fasting glucose before breakfast and BP at bedtime.',
        'p_003': 'Focus on oxygen saturation and pressure after activity.',
      });

    _clinicalDetails
      ..clear()
      ..addAll({
        'p_001': StaffPatientClinicalDetail(
          patientId: 'p_001',
          name: 'Amara Okonkwo',
          uniqueId: 'MCR-001284',
          email: 'amara.okonkwo@example.com',
          phone: '+254 712 345 678',
          health: PatientHealthProfile(
            bloodType: BloodType.oPos,
            gender: Gender.female,
            dateOfBirth: DateTime(1970, 6, 12),
            heightCm: 165,
            weightKg: 72,
            chronicConditions: const ['Type 2 Diabetes', 'Hypertension'],
            allergies: const ['Penicillin'],
            currentMedications: const ['Metformin', 'Lisinopril'],
            address: 'Nairobi, Kenya',
            locationConsent: true,
          ),
          emergencyContacts: const [
            EmergencyContact(
              id: 'ec_1',
              name: 'James Okonkwo',
              relationship: 'Spouse',
              phone: '+254 700 111 222',
              email: 'james.okonkwo@example.com',
            ),
            EmergencyContact(
              id: 'ec_2',
              name: 'Grace Okonkwo',
              relationship: 'Sister',
              phone: '+254 733 444 555',
              email: 'grace.okonkwo@example.com',
              priority: 2,
            ),
          ],
          assignedVitals: {VitalKey.bloodPressure, VitalKey.bloodGlucose},
          assignedVitalsNote:
              'Track fasting glucose before breakfast and BP at bedtime.',
        ),
      });

    _reports
      ..clear()
      ..addAll([
        ClinicalReport(
          id: 'rp_1',
          patientName: 'Amara Okonkwo',
          title: 'Quarterly diabetes review',
          createdAt: now.subtract(const Duration(days: 4)),
          body:
              'Glucose trend trending downward over 30 days. Adherence to Metformin 89%. Recommend continuing therapy.',
          published: true,
        ),
        ClinicalReport(
          id: 'rp_2',
          patientName: 'Wangari Njeri',
          title: 'Hypertensive emergency follow-up',
          createdAt: now.subtract(const Duration(days: 1)),
          body:
              'Patient presented with BP 172/108. Advised immediate ED transfer.',
        ),
      ]);

    _users
      ..clear()
      ..addAll([
        DirectoryUser(
          id: 'p_001',
          uniqueId: 'MCR-001284',
          name: 'Amara Okonkwo',
          email: 'amara.okonkwo@example.com',
          role: UserRole.patient,
          status: 'active',
          joinedAt: now.subtract(const Duration(days: 220)),
        ),
        DirectoryUser(
          id: 'p_003',
          uniqueId: 'MCR-001399',
          name: 'Wangari Njeri',
          email: 'wangari.n@example.com',
          role: UserRole.patient,
          status: 'active',
          joinedAt: now.subtract(const Duration(days: 120)),
        ),
        DirectoryUser(
          id: 'dr_01',
          uniqueId: 'MCR-DR-0231',
          name: 'Dr. Kojo Mensah',
          email: 'dr.mensah@mcare.health',
          role: UserRole.doctor,
          status: 'active',
          joinedAt: now.subtract(const Duration(days: 410)),
        ),
        DirectoryUser(
          id: 'dr_02',
          uniqueId: 'MCR-DR-0312',
          name: 'Dr. Sarah Adeyemi',
          email: 'dr.adeyemi@mcare.health',
          role: UserRole.doctor,
          status: 'active',
          joinedAt: now.subtract(const Duration(days: 380)),
        ),
        DirectoryUser(
          id: 'ma_01',
          uniqueId: 'MCR-MA-0058',
          name: 'Tendai Moyo',
          email: 'assistant@mcare.health',
          role: UserRole.mcareAssistant,
          status: 'active',
          joinedAt: now.subtract(const Duration(days: 175)),
        ),
        DirectoryUser(
          id: 'ad_01',
          uniqueId: 'MCR-AD-0014',
          name: 'Nia Chebet',
          email: 'admin@mcare.health',
          role: UserRole.admin,
          status: 'active',
          joinedAt: now.subtract(const Duration(days: 600)),
        ),
      ]);

    _approvals
      ..clear()
      ..addAll([
        HealthworkerApproval(
          id: 'ap_req_1',
          name: 'Dr. Yusuf Salim',
          email: 'yusuf.salim@example.com',
          specialty: 'Cardiology',
          licenseNumber: 'KE-MED-22941',
          appliedAt: now.subtract(const Duration(hours: 9)),
        ),
        HealthworkerApproval(
          id: 'ap_req_2',
          name: 'Dr. Linda Achieng',
          email: 'l.achieng@example.com',
          specialty: 'Endocrinology',
          licenseNumber: 'KE-MED-33122',
          appliedAt: now.subtract(const Duration(days: 1, hours: 4)),
        ),
        HealthworkerApproval(
          id: 'ap_req_3',
          name: 'Nurse Peter Kamau',
          email: 'p.kamau@example.com',
          specialty: 'Nursing',
          licenseNumber: 'KE-NUR-19002',
          appliedAt: now.subtract(const Duration(days: 2)),
        ),
      ]);

    _assignments
      ..clear()
      ..addAll([
        CareAssignment(
          id: 'as_1',
          patient: 'Amara Okonkwo',
          provider: 'Dr. Kojo Mensah',
          assignedAt: now.subtract(const Duration(days: 210)),
        ),
        CareAssignment(
          id: 'as_2',
          patient: 'Wangari Njeri',
          provider: 'Dr. Sarah Adeyemi',
          assignedAt: now.subtract(const Duration(days: 90)),
        ),
        CareAssignment(
          id: 'as_3',
          patient: 'Brian Otieno',
          provider: 'Dr. Kojo Mensah',
          assignedAt: now.subtract(const Duration(days: 14)),
          role: 'Consulting',
        ),
      ]);

    _careRequests
      ..clear()
      ..addAll([
        CareRequestItem(
          id: 'cr_1',
          patient: 'Daniel Mwangi',
          providerRequested: 'Dr. Sarah Adeyemi',
          reason: 'New-patient diabetes consultation',
          createdAt: now.subtract(const Duration(hours: 4)),
        ),
        CareRequestItem(
          id: 'cr_2',
          patient: 'Esther Wambui',
          providerRequested: 'Dr. Kojo Mensah',
          reason: 'Hypertension follow-up',
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ]);

    _mealPlans
      ..clear()
      ..addAll([
        StaffMealPlan(
          id: 'meal_1',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          title: 'Diabetic-friendly breakfast',
          mealType: MealType.breakfast,
          description:
              'High-fiber, low-GI foods. Avoid white bread and sugary cereals.',
          calories: 350,
          protein: '20g',
          carbs: '40g',
          fat: '10g',
          assignedAt: now.subtract(const Duration(days: 14)),
          assignedBy: 'Dr. Kojo Mensah',
        ),
        StaffMealPlan(
          id: 'meal_2',
          patientId: 'p_001',
          patientName: 'Amara Okonkwo',
          title: 'Low-sodium lunch',
          mealType: MealType.lunch,
          description:
              'Limit sodium to <500 mg per meal. Include lean protein.',
          calories: 450,
          protein: '35g',
          carbs: '50g',
          fat: '12g',
          assignedAt: now.subtract(const Duration(days: 14)),
          assignedBy: 'Dr. Kojo Mensah',
        ),
        StaffMealPlan(
          id: 'meal_3',
          patientId: 'p_005',
          patientName: 'Esther Wambui',
          title: 'DASH diet dinner',
          mealType: MealType.dinner,
          description:
              'DASH diet for hypertension. Emphasize vegetables, whole grains, low sodium.',
          calories: 500,
          protein: '30g',
          carbs: '55g',
          fat: '15g',
          notes: 'Avoid processed meats and canned soups.',
          assignedAt: now.subtract(const Duration(days: 7)),
          assignedBy: 'Dr. Kojo Mensah',
        ),
      ]);

    _seedDefaultVitalCatalog();

    _audit
      ..clear()
      ..addAll([
        AuditEntry(
          id: 'au_1',
          at: now.subtract(const Duration(minutes: 12)),
          actor: 'Nia Chebet (Admin)',
          action: 'Approved healthworker',
          target: 'Dr. Linda Achieng',
        ),
        AuditEntry(
          id: 'au_2',
          at: now.subtract(const Duration(hours: 3)),
          actor: 'Tendai Moyo (Assistant)',
          action: 'Assigned patient',
          target: 'Daniel Mwangi → Dr. Sarah Adeyemi',
        ),
        AuditEntry(
          id: 'au_3',
          at: now.subtract(const Duration(hours: 7)),
          actor: 'System',
          action: 'Critical alert escalated',
          target: 'Wangari Njeri — BP 172/108',
          category: 'security',
        ),
        AuditEntry(
          id: 'au_4',
          at: now.subtract(const Duration(days: 1)),
          actor: 'Dr. Kojo Mensah',
          action: 'Issued prescription',
          target: 'Amara Okonkwo — Lisinopril 10mg',
        ),
        AuditEntry(
          id: 'au_5',
          at: now.subtract(const Duration(days: 2)),
          actor: 'Nia Chebet (Admin)',
          action: 'Updated permissions',
          target: 'Tendai Moyo — added approve_healthworkers',
        ),
      ]);

    _system
      ..clear()
      ..addAll([
        SystemConfigSection(
          key: 'sms_alerts',
          title: 'SMS alerts for critical vitals',
          description: 'Send Twilio SMS for severity ≥ 4.',
          category: 'Notifications',
          value: true,
        ),
        SystemConfigSection(
          key: 'push_notifications',
          title: 'Push notifications',
          description: 'Firebase Cloud Messaging for mobile apps.',
          category: 'Notifications',
          value: true,
        ),
        SystemConfigSection(
          key: 'email_digests',
          title: 'Daily email digests',
          description: 'Send morning summary to assigned doctors.',
          category: 'Notifications',
          value: false,
        ),
        SystemConfigSection(
          key: 'allow_self_registration',
          title: 'Allow self-registration (Patients)',
          description: 'When off, all signups require an admin invite.',
          category: 'Access',
          value: true,
        ),
        SystemConfigSection(
          key: 'two_factor_required',
          title: 'Require 2FA for staff',
          description:
              'All admin, assistant and doctor accounts must use TOTP.',
          category: 'Access',
          value: false,
        ),
        SystemConfigSection(
          key: 'audit_retention_365',
          title: 'Audit retention 365 days',
          description: 'Older entries archive to cold storage automatically.',
          category: 'Data',
          value: true,
        ),
        SystemConfigSection(
          key: 'anonymise_exports',
          title: 'Anonymise data exports',
          description: 'Strip PII before any CSV/JSON export.',
          category: 'Data',
          value: true,
        ),
        SystemConfigSection(
          key: 'maintenance_mode',
          title: 'Maintenance mode',
          description: 'Block non-admin sessions during upgrades.',
          category: 'Runtime',
          value: false,
        ),
      ]);

    _recomputeUnreadAlerts();
    _syncToNotificationCenter();
    notifyListeners();
  }

  /// API rehydrate — replaces the same buckets `seedDemo()` populates with
  /// freshly mapped rows from `/doctor/session`. Admin-only buckets such as
  /// the global user directory, audit log, and system configuration are not
  /// part of a live doctor session.
  void seedFromApi({
    required List<StaffPatient> patients,
    required List<StaffAlert> alerts,
    required List<StaffAppointment> appointments,
    required List<StaffPrescription> prescriptions,
    required List<ClinicalReport> reports,
    required List<StaffPatientRequest> vitalRequests,
    required List<CareRequestItem> careRequests,
    List<StaffPatientSos>? sosEvents,
    List<VitalCatalogEntry>? vitalCatalog,
    List<StaffMealPlan>? mealPlans,
    List<StaffPatientVitalReading>? vitalReadings,
  }) {
    _patients
      ..clear()
      ..addAll(patients);
    _alerts
      ..clear()
      ..addAll(alerts);
    _appointments
      ..clear()
      ..addAll(appointments);
    _prescriptions
      ..clear()
      ..addAll(prescriptions);
    _reports
      ..clear()
      ..addAll(reports);
    _requests
      ..clear()
      ..addAll(vitalRequests);
    _careRequests
      ..clear()
      ..addAll(careRequests);
    if (sosEvents != null) {
      _sosEvents
        ..clear()
        ..addAll(sosEvents);
    }
    if (mealPlans != null) {
      _mealPlans
        ..clear()
        ..addAll(mealPlans);
    }
    if (vitalReadings != null) {
      _vitalReadings
        ..clear()
        ..addAll(vitalReadings);
    }
    mergeVitalCatalog(vitalCatalog ?? const []);
    _recomputeUnreadAlerts();
    _syncToNotificationCenter();
    final fp = _computeApiFingerprint();
    if (fp != _lastApiFingerprint) {
      _lastApiFingerprint = fp;
      notifyListeners();
    }
  }

  int? _lastApiFingerprint;

  int _computeApiFingerprint() {
    return Object.hash(
      Object.hashAll(
        _patients.map(
          (p) =>
              '${p.id}:${p.name}:${p.age}:${p.sex}:${p.condition}:'
              '${p.risk.name}:${p.lastReading.toIso8601String()}:'
              '${p.unreadAlerts}:${p.assignedDoctor}',
        ),
      ),
      Object.hashAll(
        _alerts.map(
          (a) =>
              '${a.id}:${a.value}:${a.severity.name}:'
              '${a.acknowledged}:${a.resolved}:${a.resolutionNote}:'
              '${a.resolutionAction}:${a.resolutionCustomAction}',
        ),
      ),
      Object.hashAll(
        _appointments.map(
          (a) =>
              '${a.id}:${a.startAt.toIso8601String()}:${a.type.name}:'
              '${a.status.name}:${a.reason}:${a.locationOrLink}:'
              '${a.cancellationReason}:${a.durationMinutes}',
        ),
      ),
      Object.hashAll(
        _prescriptions.map(
          (p) =>
              '${p.id}:${p.drug}:${p.dosage}:${p.frequency}:'
              '${p.duration}:${p.status}',
        ),
      ),
      Object.hashAll(
        _reports.map((r) => '${r.id}:${r.title}:${r.body}:${r.published}'),
      ),
      Object.hashAll(
        _requests.map((r) => '${r.id}:${r.type}:${r.summary}:${r.status}'),
      ),
      Object.hashAll(
        _careRequests.map(
          (r) =>
              '${r.id}:${r.status}:${r.assignedProviderId}:'
              '${r.assignedProviderName}:${r.assignmentRole}:'
              '${r.decisionNote}:${r.decidedAt?.toIso8601String()}',
        ),
      ),
      Object.hashAll(
        _sosEvents.map(
          (e) => '${e.id}:${e.status}:${e.respondedBy}:${e.locationLabel}',
        ),
      ),
      Object.hashAll(
        _mealPlans.map(
          (m) =>
              '${m.id}:${m.title}:${m.description}:${m.calories}:'
              '${m.protein}:${m.carbs}:${m.fat}:${m.notes}',
        ),
      ),
      Object.hashAll(
        _vitalReadings.map(
          (r) =>
              '${r.id}:${r.patientId}:${r.vital.name}:${r.value}:'
              '${r.risk.name}:${r.recordedAt.toIso8601String()}:${r.note}',
        ),
      ),
    );
  }

  /// Rebuild listeners only when session buckets actually changed.
  /// Trigger UI rebuilds after in-place mutations (e.g. unlock / temp password).
  void notifyDirectoryChanged() => notifyListeners();

  void notifyIfSessionChanged() {
    final fp = _computeApiFingerprint();
    if (fp != _lastApiFingerprint) {
      _lastApiFingerprint = fp;
      notifyListeners();
    }
  }

  /// Replace SOS events from admin API sync (keeps other staff buckets).
  void mergeSosEvents(List<StaffPatientSos> events) {
    for (final e in events) {
      if (patientById(e.patientId) == null &&
          e.patientName != null &&
          e.patientName!.isNotEmpty) {
        _patients.add(
          StaffPatient(
            id: e.patientId,
            name: e.patientName!,
            age: 0,
            sex: '—',
            condition: 'SOS patient',
            risk: RiskLevel.critical,
            lastReading: e.triggeredAt,
            assignedDoctor: '',
          ),
        );
      }
    }
    _sosEvents
      ..clear()
      ..addAll(events);
    _syncToNotificationCenter();
    notifyListeners();
  }

  /// Replace the directory user list from `GET /admin/users` (idempotent by id).
  void mergeUsers(List<DirectoryUser> users) {
    _users
      ..clear()
      ..addAll(users);
    notifyListeners();
  }

  void mergeApprovals(List<HealthworkerApproval> approvals) {
    _approvals
      ..clear()
      ..addAll(approvals);
    notifyListeners();
  }

  void patchApprovalFromApi(Map<String, dynamic> json) {
    final updated = StaffMapper.approvalFromApi(json);
    final i = _approvals.indexWhere((a) => a.id == updated.id);
    if (i == -1) {
      _approvals.add(updated);
    } else {
      _approvals[i] = updated;
    }
    notifyListeners();
  }

  void mergeAssignments(List<CareAssignment> assignments) {
    _assignments
      ..clear()
      ..addAll(assignments);
    notifyListeners();
  }

  void mergeCareRequests(List<CareRequestItem> requests) {
    _careRequests
      ..clear()
      ..addAll(requests);
    notifyListeners();
  }

  void mergeAudit(List<AuditEntry> entries) {
    _audit
      ..clear()
      ..addAll(entries);
    notifyListeners();
  }

  void mergeSystemSettings(List<SystemConfigSection> settings) {
    _system
      ..clear()
      ..addAll(settings);
    notifyListeners();
  }

  /// Clears admin-specific mock buckets before API hydration.
  /// Drop every admin-scoped bucket.
  ///
  /// Only for leaving the workspace — a role switch or sign-out. It is not a
  /// refresh step: the admin sync used to call this *before* fetching, so the
  /// app held zero alerts for the length of the round trip and any rebuild in
  /// that window painted the dashboard all-clear over live emergencies. Each
  /// `merge*` replaces its own bucket, which is what a refresh should do.
  void clearAdminBuckets() {
    _users.clear();
    _approvals.clear();
    _assignments.clear();
    _careRequests.clear();
    _audit.clear();
    _sosEvents.clear();
    _alerts.clear();
    // Keep vital catalog if already loaded; system settings replaced when fetched.
  }

  /// How many session refreshes are in flight.
  ///
  /// Surfaces on [isSyncing] so a screen can tell "nothing outstanding" apart
  /// from "not loaded yet" and refuse to render an all-clear it cannot stand
  /// behind.
  int _syncDepth = 0;

  bool get isSyncing => _syncDepth > 0;

  void beginSync() {
    _syncDepth++;
  }

  void endSync() {
    if (_syncDepth > 0) _syncDepth--;
    if (_syncDepth == 0) notifyListeners();
  }

  /// Replaces system-wide alert rows from admin session / alerts API.
  void mergeAlerts(List<StaffAlert> alerts) {
    _alerts
      ..clear()
      ..addAll(alerts);
    _recomputeUnreadAlerts();
    _syncToNotificationCenter();
    notifyListeners();
  }

  Future<bool> adminResolveSos(
    String id, {
    String status = 'resolved',
    String? resolution,
    String? resolutionNote,
  }) {
    StaffPatientSos? before;
    for (final e in _sosEvents) {
      if (e.id == id) {
        before = e;
        break;
      }
    }
    if (before == null) return Future.value(false);

    return _doctorMutation(
      apply: () {
        final i = _sosEvents.indexWhere((e) => e.id == id);
        if (i == -1) return;
        final e = _sosEvents[i];
        if (status == 'resolved' || status == 'falseAlarm') {
          _sosEvents.removeAt(i);
        } else {
          _sosEvents[i] = StaffPatientSos(
            id: e.id,
            patientId: e.patientId,
            patientName: e.patientName,
            kind: e.kind,
            status: status,
            triggeredAt: e.triggeredAt,
            locationLabel: e.locationLabel,
            note: e.note,
            latitude: e.latitude,
            longitude: e.longitude,
            respondedBy: e.respondedBy,
          );
        }
      },
      revert: () {
        if (status == 'resolved' || status == 'falseAlarm') {
          _sosEvents.add(before!);
        } else {
          final i = _sosEvents.indexWhere((e) => e.id == id);
          if (i != -1) _sosEvents[i] = before!;
        }
      },
      apiCall: () => AdminApi.instance.resolveSos(
        id,
        status: status,
        resolution: resolution,
        resolutionNote: resolutionNote,
      ),
    );
  }

  /// Updates an SOS through the API owned by the signed-in staff role.
  ///
  /// SOS surfaces are shared by doctors, admins, and assistants. Centralising
  /// this switch prevents a shared action from accidentally calling the
  /// doctor endpoint while an admin or assistant is signed in.
  Future<bool> updateSosForCurrentRole(
    String id, {
    String status = 'resolved',
    String? resolution,
    String? resolutionNote,
  }) {
    final role = AuthState.instance.user?.role;
    if (role == UserRole.admin || role == UserRole.mcareAssistant) {
      return adminResolveSos(
        id,
        status: status,
        resolution: resolution,
        resolutionNote: resolutionNote,
      );
    }
    return resolveSos(
      id,
      status: status,
      resolution: resolution,
      resolutionNote: resolutionNote,
    );
  }

  /// Merges per-patient detail from `GET /doctor/patients/{id}`.
  void mergePatientDetail(String patientId, Map<String, dynamic> data) {
    final patientJson =
        (data['patient'] as Map?)?.cast<String, dynamic>() ?? const {};
    final patientName =
        patientJson['name'] as String? ?? patientById(patientId)?.name ?? '';

    final assignedRaw = data['assigned_vitals'] as List? ?? const [];
    final assigned = assignedRaw
        .map((e) => PatientProfileMapper.vitalKeyFromApi(e as String))
        .toSet();
    _assignedVitalsByPatient[patientId] = assigned;
    final assignmentNoteRaw = data['assigned_vitals_note'] as String?;
    if (assignmentNoteRaw == null || assignmentNoteRaw.trim().isEmpty) {
      _staffAssignedVitalNotes.remove(patientId);
    } else {
      _staffAssignedVitalNotes[patientId] = assignmentNoteRaw.trim();
    }

    final healthJson = patientJson['health'] as Map<String, dynamic>?;
    final contactsRaw = patientJson['emergency_contacts'] as List? ?? const [];
    _clinicalDetails[patientId] = StaffPatientClinicalDetail(
      patientId: patientId,
      name: patientName,
      uniqueId: patientJson['unique_id'] as String?,
      email: patientJson['email'] as String?,
      phone: patientJson['phone'] as String?,
      health: healthJson == null
          ? null
          : PatientProfileMapper.healthFromApi(healthJson),
      emergencyContacts: contactsRaw
          .map(
            (e) => PatientProfileMapper.contactFromApi(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      assignedVitals: assigned,
      assignedVitalsNote: assignmentNoteRaw?.trim(),
    );

    _documents.removeWhere((d) => d.patientId == patientId);
    for (final raw in data['documents'] as List? ?? const []) {
      _documents.add(
        StaffMapper.documentFromApi(
          (raw as Map).cast<String, dynamic>(),
          patientId: patientId,
        ),
      );
    }

    _sosEvents.removeWhere((e) => e.patientId == patientId);
    for (final raw in data['sos_events'] as List? ?? const []) {
      _sosEvents.add(
        StaffMapper.sosFromApi(
          (raw as Map).cast<String, dynamic>(),
          patientId: patientId,
        ),
      );
    }

    _vitalReadings.removeWhere((v) => v.patientId == patientId);
    for (final raw in data['vitals'] as List? ?? const []) {
      _vitalReadings.add(
        StaffMapper.vitalReadingFromApi(
          (raw as Map).cast<String, dynamic>(),
          patientId: patientId,
        ),
      );
    }

    _requests.removeWhere((r) => r.patientId == patientId);
    for (final raw in data['vital_report_requests'] as List? ?? const []) {
      _requests.add(
        StaffMapper.vitalReportRequestFromApi(
          (raw as Map).cast<String, dynamic>(),
        ),
      );
    }

    _prescriptions.removeWhere((r) => r.patientId == patientId);
    for (final raw in data['medications'] as List? ?? const []) {
      final m = (raw as Map).cast<String, dynamic>();
      m['patient_id'] ??= patientId;
      m['patient_name'] ??= patientName;
      _prescriptions.add(StaffMapper.prescriptionFromApi(m));
    }

    _reports.removeWhere((r) => r.patientName == patientName);
    for (final raw in data['reports'] as List? ?? const []) {
      final m = (raw as Map).cast<String, dynamic>();
      m['patient_name'] ??= patientName;
      _reports.add(StaffMapper.reportFromApi(m));
    }

    _alerts.removeWhere((a) => a.patientId == patientId);
    for (final raw in data['alerts'] as List? ?? const []) {
      final m = (raw as Map).cast<String, dynamic>();
      m['patient_id'] ??= patientId;
      m['patient_name'] ??= patientName;
      m['severity'] ??= m['kind'] == 'vital_critical' || m['kind'] == 'sos'
          ? 'critical'
          : 'warning';
      m['acknowledged'] ??= m['read'] ?? false;
      _alerts.add(StaffMapper.alertFromApi(m));
    }

    _syncToNotificationCenter();
    notifyListeners();
  }

  /// Merge admin patient profile payload into staff cache.
  void mergeAdminPatientProfile(String patientId, Map<String, dynamic> data) {
    final patientJson =
        (data['patient'] as Map?)?.cast<String, dynamic>() ?? const {};
    final assignedRaw = data['assigned_vitals'] as List? ?? const [];
    final assigned = assignedRaw
        .map((e) => PatientProfileMapper.vitalKeyFromApi(e as String))
        .toSet();
    _assignedVitalsByPatient[patientId] = assigned;
    final assignmentNoteRaw = data['assigned_vitals_note'] as String?;
    if (assignmentNoteRaw == null || assignmentNoteRaw.trim().isEmpty) {
      _staffAssignedVitalNotes.remove(patientId);
    } else {
      _staffAssignedVitalNotes[patientId] = assignmentNoteRaw.trim();
    }

    final healthJson = data['health'] as Map<String, dynamic>?;
    final contactsRaw = data['emergency_contacts'] as List? ?? const [];
    final joinedRaw = patientJson['created_at'] as String?;

    _clinicalDetails[patientId] = StaffPatientClinicalDetail(
      patientId: patientId,
      name: patientJson['name'] as String? ?? '',
      uniqueId: patientJson['unique_id'] as String?,
      email: patientJson['email'] as String?,
      phone: patientJson['phone'] as String?,
      health: healthJson == null
          ? null
          : PatientProfileMapper.healthFromApi(healthJson),
      emergencyContacts: contactsRaw
          .map(
            (e) => PatientProfileMapper.contactFromApi(
              (e as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
      assignedVitals: assigned,
      assignedVitalsNote: assignmentNoteRaw?.trim(),
      approvalStatus: patientJson['approval_status'] as String?,
      joinedAt: joinedRaw == null ? null : DateTime.tryParse(joinedRaw),
    );
    notifyListeners();
  }

  /// Doctor assigns vitals the patient must track. Optimistic local update
  /// with API sync when backend is enabled.
  Future<bool> updateAssignedVitalsForPatient({
    required String patientId,
    required Set<VitalKey> vitals,
    String? note,
  }) async {
    if (vitals.isEmpty) return false;

    final before = Set<VitalKey>.from(
      _assignedVitalsByPatient[patientId] ?? const {},
    );
    final beforeNote = _assignedVitalsNoteFor(patientId);
    final next = Set<VitalKey>.from(vitals);
    final noteValue = note?.trim();
    final removed = before.difference(next);
    final removedOverrideSnapshot = removed.isEmpty
        ? const <PatientVitalThreshold>[]
        : _vitalOverrides
              .where(
                (o) => o.patientId == patientId && removed.contains(o.vital),
              )
              .map(
                (o) => PatientVitalThreshold(
                  patientId: o.patientId,
                  vital: o.vital,
                  normalMin: o.normalMin,
                  normalMax: o.normalMax,
                  warningLow: o.warningLow,
                  warningHigh: o.warningHigh,
                  criticalLow: o.criticalLow,
                  criticalHigh: o.criticalHigh,
                  setBy: o.setBy,
                  updatedAt: o.updatedAt,
                  note: o.note,
                ),
              )
              .toList(growable: false);

    _assignedVitalsByPatient[patientId] = next;

    final detail = _clinicalDetails[patientId];
    if (detail != null) {
      if (noteValue == null || noteValue.isEmpty) {
        _staffAssignedVitalNotes.remove(patientId);
        _clinicalDetails[patientId] = detail.copyWith(
          assignedVitals: next,
          clearAssignedVitalsNote: true,
        );
      } else {
        _staffAssignedVitalNotes[patientId] = noteValue;
        _clinicalDetails[patientId] = detail.copyWith(
          assignedVitals: next,
          assignedVitalsNote: noteValue,
        );
      }
    } else {
      _setAssignedVitalsNote(patientId, noteValue);
      final patient = patientById(patientId);
      if (patient != null && noteValue != null && noteValue.isNotEmpty) {
        _clinicalDetails[patientId] = StaffPatientClinicalDetail(
          patientId: patientId,
          name: patient.name,
          assignedVitals: next,
          assignedVitalsNote: noteValue,
        );
      }
    }

    // If vitals are de-assigned, also remove any per-patient threshold /
    // alert configuration so the removed vital returns to default behavior.
    if (removed.isNotEmpty) {
      _vitalOverrides.removeWhere(
        (o) => o.patientId == patientId && removed.contains(o.vital),
      );
    }
    notifyListeners();

    if (!AppEnv.backendEnabled) return true;

    try {
      final role = AuthState.instance.user?.role;
      final vitalKeys = next.map((v) => v.name).toList();
      final keys = (role == UserRole.admin || role == UserRole.mcareAssistant)
          ? await AdminApi.instance.updateAssignedVitals(
              patientUserId: patientId,
              vitalKeys: vitalKeys,
              note: noteValue,
            )
          : await DoctorApi.instance.updateAssignedVitals(
              patientUserId: patientId,
              vitalKeys: vitalKeys,
              note: noteValue,
            );
      final synced = keys.map(PatientProfileMapper.vitalKeyFromApi).toSet();
      _assignedVitalsByPatient[patientId] = synced;
      final d = _clinicalDetails[patientId];
      if (d != null) {
        _clinicalDetails[patientId] = d.copyWith(assignedVitals: synced);
      }
      notifyListeners();
      return true;
    } catch (_) {
      _assignedVitalsByPatient[patientId] = before;
      _setAssignedVitalsNote(patientId, beforeNote);
      if (removed.isNotEmpty && removedOverrideSnapshot.isNotEmpty) {
        _vitalOverrides.removeWhere(
          (o) => o.patientId == patientId && removed.contains(o.vital),
        );
        _vitalOverrides.addAll(removedOverrideSnapshot);
      }
      if (detail != null) {
        _clinicalDetails[patientId] = detail.copyWith(assignedVitals: before);
      }
      notifyListeners();
      return false;
    }
  }

  String? _patientIdByName(String name) {
    final trimmed = name.trim().toLowerCase();
    for (final p in _patients) {
      if (p.name.trim().toLowerCase() == trimmed) return p.id;
    }
    return null;
  }

  Future<bool> _doctorMutation({
    required void Function() apply,
    required void Function() revert,
    Future<void> Function()? apiCall,
  }) async {
    apply();
    _recomputeUnreadAlerts();
    _syncToNotificationCenter();
    notifyListeners();
    if (!AppEnv.backendEnabled || apiCall == null) return true;
    try {
      await apiCall();
      return true;
    } catch (_) {
      revert();
      _recomputeUnreadAlerts();
      _syncToNotificationCenter();
      notifyListeners();
      return false;
    }
  }

  List<AnalyticsKpi> kpis() {
    final user = AuthState.instance.user;
    if (user?.role == UserRole.admin || user?.role == UserRole.mcareAssistant) {
      return adminKpis();
    }

    final caseload = assignedPatientsForDoctor();
    final activePatients = caseload.length;
    final assignedIds = caseload.map((p) => p.id).toSet();
    final activeAlerts = _alerts
        .where(
          (a) =>
              !a.acknowledged &&
              !a.resolved &&
              assignedIds.contains(a.patientId),
        )
        .length;
    final pendingApprovals = _approvals
        .where((a) => a.status == 'pending')
        .length;
    // Deltas require a historical baseline the client does not have offline, so
    // they are omitted here (the API path supplies real trends when available).
    return [
      AnalyticsKpi(
        label: 'Active patients',
        value: '$activePatients',
        helper: 'caseload',
      ),
      AnalyticsKpi(
        label: 'Open alerts',
        value: '$activeAlerts',
        helper: 'unacknowledged',
      ),
      AnalyticsKpi(
        label: 'Pending approvals',
        value: '$pendingApprovals',
        helper: 'healthworker queue',
      ),
      AnalyticsKpi(
        label: 'Avg. response time',
        value: '—',
        helper: 'alert acknowledgement',
      ),
    ];
  }

  /// Admin / assistant KPI tiles — uses directory users + system-wide alerts.
  List<AnalyticsKpi> adminKpis() {
    final activePatients = _users
        .where((u) => u.role == UserRole.patient && u.status == 'active')
        .length;
    final openAlerts = _alerts
        .where((a) => !a.acknowledged && !a.resolved)
        .length;
    final pendingApprovals = _approvals
        .where((a) => a.status == 'pending')
        .length;
    // Deltas require a historical baseline the client does not have offline, so
    // they are omitted here (the API path supplies real trends when available).
    return [
      AnalyticsKpi(
        label: 'Active patients',
        value: '$activePatients',
        helper: 'currently active',
      ),
      AnalyticsKpi(
        label: 'Open alerts',
        value: '$openAlerts',
        helper: 'unacknowledged',
      ),
      AnalyticsKpi(
        label: 'Pending approvals',
        value: '$pendingApprovals',
        helper: 'healthworker queue',
      ),
      AnalyticsKpi(
        label: 'Avg. response time',
        value: '—',
        helper: 'alert acknowledgement',
      ),
    ];
  }

  /// Keep per-patient unread counts aligned with open alert rows.
  void _recomputeUnreadAlerts() {
    for (final p in _patients) {
      p.unreadAlerts = _alerts
          .where((a) => a.patientId == p.id && !a.acknowledged && !a.resolved)
          .length;
    }
  }

  /// Republish a snapshot of caseload alerts + active SOS + pending
  /// requests into the shared NotificationState so the bell badge and
  /// notifications inbox reflect what the doctor needs to act on.
  /// Called from every mutation that changes alert/SOS/request status.
  void _syncToNotificationCenter() {
    final user = AuthState.instance.user;
    final isStaff =
        user != null &&
        (user.role == UserRole.doctor ||
            user.role == UserRole.admin ||
            user.role == UserRole.mcareAssistant);
    if (!isStaff) return;

    // Doctors are scoped to their caseload. Admins and assistants are not
    // scoped at all: `/admin/session` ships alerts and SOS but not the patient
    // roster, so intersecting with `_patients` dropped notifications for every
    // patient the current screen happened not to have loaded.
    final assigned = user.role == UserRole.doctor
        ? assignedPatientsForDoctor().map((p) => p.id).toSet()
        : null;
    // A null patient id means the item is not tied to one (an unassigned
    // appointment) — it belongs to whoever is looking, as it always did.
    bool inScope(String? patientId) =>
        assigned == null || patientId == null || assigned.contains(patientId);

    final items = <AppNotification>[];

    for (final a in _alerts) {
      if (!inScope(a.patientId)) continue;
      if (a.resolved) continue;
      items.add(
        AppNotification(
          id: 'staff_alert_${a.id}',
          kind: a.severity == RiskLevel.critical
              ? NotificationKind.vitalAlert
              : NotificationKind.vitalAlert,
          title: '${a.patientName} · ${a.vital.label} ${a.severity.label}',
          body: '${a.vital.shortLabel} ${a.value}',
          createdAt: a.createdAt,
          read: a.acknowledged,
          resolved: a.resolved,
          resolvedAt: a.resolved ? DateTime.now() : null,
          actionRoute: RouteNames.doctorAlerts,
        ),
      );
    }

    for (final s in _sosEvents) {
      if (!inScope(s.patientId)) continue;
      final sosRoute = switch (user.role) {
        UserRole.doctor => RouteNames.doctorSos,
        UserRole.admin => RouteNames.adminSos,
        UserRole.mcareAssistant => RouteNames.assistantSos,
        _ => RouteNames.doctorSos,
      };
      items.add(
        AppNotification(
          id: 'staff_sos_${s.id}',
          kind: NotificationKind.sos,
          title: 'SOS · ${_patientNameFor(s.patientId)}',
          body: s.locationLabel == null
              ? s.kindLabel
              : '${s.kindLabel} · ${s.locationLabel}',
          createdAt: s.triggeredAt,
          read: !s.isActive,
          resolved: !s.isActive,
          resolvedAt: s.isActive ? null : DateTime.now(),
          actionRoute: sosRoute,
          actionArguments: {'patientId': s.patientId, 'eventId': s.id},
        ),
      );
    }

    for (final r in _requests) {
      if (!inScope(r.patientId)) continue;
      items.add(
        AppNotification(
          id: 'staff_req_${r.id}',
          kind: NotificationKind.careRequest,
          title: '${_patientNameFor(r.patientId)} · ${r.type}',
          body: r.summary,
          createdAt: r.createdAt,
          read: !r.isPending,
          resolved: r.status == 'fulfilled',
          resolvedAt: r.status == 'fulfilled' ? DateTime.now() : null,
          actionRoute: RouteNames.doctorInbox,
        ),
      );
    }

    // Upcoming appointments within the next 24 hours
    final soon = DateTime.now().add(const Duration(hours: 24));
    for (final a in _appointments) {
      if (!inScope(a.patientId)) continue;
      if (!a.isUpcoming || a.startAt.isAfter(soon)) continue;
      items.add(
        AppNotification(
          id: 'staff_appt_${a.id}',
          kind: NotificationKind.appointment,
          title: '${a.patientName} · ${a.type.label}',
          body: 'Scheduled ${_shortTime(a.startAt)}',
          createdAt: a.startAt.subtract(const Duration(hours: 1)),
          read: false,
          resolved: false,
          actionRoute: RouteNames.doctorAppointments,
        ),
      );
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    NotificationState.instance.seedStaffComputedNotifications(items);
  }

  static String _shortTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $suffix';
  }

  String _patientNameFor(String id) => patientById(id)?.name ?? 'Patient';

  void clear() {
    _patients.clear();
    _alerts.clear();
    _prescriptions.clear();
    _appointments.clear();
    _reports.clear();
    _users.clear();
    _approvals.clear();
    _assignments.clear();
    _careRequests.clear();
    _vitalCatalog.clear();
    _audit.clear();
    _system.clear();
    _documents.clear();
    _sosEvents.clear();
    _requests.clear();
    _vitalReadings.clear();
    _mealPlans.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Optimistic mutations
  // -------------------------------------------------------------------------

  Future<bool> acknowledgeAlert(String id) {
    StaffAlert? before;
    for (final a in _alerts) {
      if (a.id == id) {
        before = StaffAlert(
          id: a.id,
          patientId: a.patientId,
          patientName: a.patientName,
          vital: a.vital,
          value: a.value,
          severity: a.severity,
          createdAt: a.createdAt,
          acknowledged: a.acknowledged,
          resolved: a.resolved,
          resolutionNote: a.resolutionNote,
          resolutionAction: a.resolutionAction,
          resolutionCustomAction: a.resolutionCustomAction,
        );
        break;
      }
    }
    if (before == null) return Future.value(false);

    return _doctorMutation(
      apply: () {
        for (final a in _alerts) {
          if (a.id == id) a.acknowledged = true;
        }
      },
      revert: () {
        for (final a in _alerts) {
          if (a.id == id) a.acknowledged = before!.acknowledged;
        }
      },
      apiCall: () {
        final role = AuthState.instance.user?.role;
        if (role == UserRole.admin || role == UserRole.mcareAssistant) {
          return AdminApi.instance.acknowledgeAlert(id);
        }
        return DoctorApi.instance.acknowledgeAlert(id);
      },
    );
  }

  Future<bool> resolveAlert(
    String id, {
    required String actionTaken,
    required String note,
    String? customAction,
  }) {
    StaffAlert? before;
    for (final a in _alerts) {
      if (a.id == id) {
        before = StaffAlert(
          id: a.id,
          patientId: a.patientId,
          patientName: a.patientName,
          vital: a.vital,
          value: a.value,
          severity: a.severity,
          createdAt: a.createdAt,
          acknowledged: a.acknowledged,
          resolved: a.resolved,
          resolutionNote: a.resolutionNote,
          resolutionAction: a.resolutionAction,
          resolutionCustomAction: a.resolutionCustomAction,
        );
        break;
      }
    }
    if (before == null) return Future.value(false);

    return _doctorMutation(
      apply: () {
        for (final a in _alerts) {
          if (a.id == id) {
            a.acknowledged = true;
            a.resolved = true;
            a.resolutionNote = note;
            a.resolutionAction = actionTaken;
            a.resolutionCustomAction = customAction;
          }
        }
      },
      revert: () {
        for (final a in _alerts) {
          if (a.id == id) {
            a.acknowledged = before!.acknowledged;
            a.resolved = before.resolved;
            a.resolutionNote = before.resolutionNote;
            a.resolutionAction = before.resolutionAction;
            a.resolutionCustomAction = before.resolutionCustomAction;
          }
        }
      },
      apiCall: () {
        final role = AuthState.instance.user?.role;
        if (role == UserRole.admin || role == UserRole.mcareAssistant) {
          return AdminApi.instance.resolveAlert(
            id,
            actionTaken: actionTaken,
            note: note,
            customAction: customAction,
          );
        }
        return DoctorApi.instance.resolveAlert(
          id,
          actionTaken: actionTaken,
          note: note,
          customAction: customAction,
        );
      },
    );
  }

  Future<bool> resolveSos(
    String id, {
    String status = 'resolved',
    String? resolution,
    String? resolutionNote,
  }) {
    StaffPatientSos? before;
    for (final e in _sosEvents) {
      if (e.id == id) {
        before = e;
        break;
      }
    }
    if (before == null) return Future.value(false);

    return _doctorMutation(
      apply: () {
        final i = _sosEvents.indexWhere((e) => e.id == id);
        if (i == -1) return;
        final e = _sosEvents[i];
        if (status == 'resolved' || status == 'falseAlarm') {
          _sosEvents.removeAt(i);
        } else {
          _sosEvents[i] = StaffPatientSos(
            id: e.id,
            patientId: e.patientId,
            patientName: e.patientName,
            kind: e.kind,
            status: status,
            triggeredAt: e.triggeredAt,
            locationLabel: e.locationLabel,
            note: e.note,
            latitude: e.latitude,
            longitude: e.longitude,
            respondedBy: e.respondedBy,
          );
        }
      },
      revert: () {
        if (status == 'resolved' || status == 'falseAlarm') {
          _sosEvents.add(before!);
        } else {
          final i = _sosEvents.indexWhere((e) => e.id == id);
          if (i != -1) _sosEvents[i] = before!;
        }
      },
      apiCall: () => DoctorApi.instance.resolveSos(
        id,
        status: status,
        resolution: resolution,
        resolutionNote: resolutionNote,
      ),
    );
  }

  Future<bool> fulfillRequest(String id) {
    StaffPatientRequest? before;
    for (final r in _requests) {
      if (r.id == id) {
        before = r;
        break;
      }
    }
    if (before == null) return Future.value(false);

    return _doctorMutation(
      apply: () {
        for (var i = 0; i < _requests.length; i++) {
          if (_requests[i].id == id) {
            final r = _requests[i];
            _requests[i] = StaffPatientRequest(
              id: r.id,
              patientId: r.patientId,
              type: r.type,
              summary: r.summary,
              status: 'fulfilled',
              createdAt: r.createdAt,
            );
          }
        }
      },
      revert: () {
        for (var i = 0; i < _requests.length; i++) {
          if (_requests[i].id == id) _requests[i] = before!;
        }
      },
      apiCall: () => DoctorApi.instance.fulfillVitalReportRequest(id),
    );
  }

  /// Escalate a pending vital-report request to the next responder tier
  /// (assistant → admin) on the backend. Locally the request drops off the
  /// doctor's actionable list until the next session sync reflects the new
  /// responder.
  Future<bool> escalateRequest(String id) {
    StaffPatientRequest? before;
    for (final r in _requests) {
      if (r.id == id) {
        before = r;
        break;
      }
    }
    if (before == null) return Future.value(false);

    return _doctorMutation(
      apply: () {
        for (var i = 0; i < _requests.length; i++) {
          if (_requests[i].id == id) {
            final r = _requests[i];
            _requests[i] = StaffPatientRequest(
              id: r.id,
              patientId: r.patientId,
              type: r.type,
              summary: r.summary,
              status: 'escalated',
              createdAt: r.createdAt,
            );
          }
        }
      },
      revert: () {
        for (var i = 0; i < _requests.length; i++) {
          if (_requests[i].id == id) _requests[i] = before!;
        }
      },
      apiCall: () => DoctorApi.instance.escalateVitalReportRequest(id),
    );
  }

  Future<bool> addPrescription(StaffPrescription rx) {
    _prescriptions.insert(0, rx);
    notifyListeners();
    if (!AppEnv.backendEnabled) return Future.value(true);

    return DoctorApi.instance
        .issuePrescription(
          patientUserId: rx.patientId,
          name: rx.drug,
          dosage: rx.dosage,
          frequency: rx.frequency,
          startDate: rx.issuedAt,
        )
        .then((data) {
          if (data != null) {
            final rxJson = (data['prescription'] as Map?)
                ?.cast<String, dynamic>();
            if (rxJson != null) {
              rxJson['patient_id'] ??= rx.patientId;
              rxJson['patient_name'] ??= rx.patientName;
              rxJson['drug'] ??= rxJson['name'];
              final i = _prescriptions.indexWhere((p) => p.id == rx.id);
              if (i != -1) {
                _prescriptions[i] = StaffMapper.prescriptionFromApi(rxJson);
                notifyListeners();
              }
            }
          }
          return true;
        })
        .catchError((_) {
          _prescriptions.removeWhere((p) => p.id == rx.id);
          notifyListeners();
          return false;
        });
  }

  Future<bool> addReport(ClinicalReport report, {String? patientUserId}) {
    _reports.insert(0, report);
    notifyListeners();
    if (!AppEnv.backendEnabled) return Future.value(true);

    final pid = patientUserId ?? _patientIdByName(report.patientName);
    if (pid == null) {
      _reports.removeWhere((r) => r.id == report.id);
      notifyListeners();
      return Future.value(false);
    }

    return DoctorApi.instance
        .saveReport(
          patientUserId: pid,
          title: report.title,
          body: report.body,
          publish: report.published,
        )
        .then((data) {
          if (data != null) {
            final repJson = (data['report'] as Map?)?.cast<String, dynamic>();
            if (repJson != null) {
              repJson['patient_name'] ??= report.patientName;
              final i = _reports.indexWhere((r) => r.id == report.id);
              if (i != -1) {
                _reports[i] = StaffMapper.reportFromApi(repJson);
                notifyListeners();
              }
            }
          }
          return true;
        })
        .catchError((_) {
          _reports.removeWhere((r) => r.id == report.id);
          notifyListeners();
          return false;
        });
  }

  Future<bool> publishReport(String id) {
    ClinicalReport? before;
    for (final r in _reports) {
      if (r.id == id) {
        before = r;
        break;
      }
    }
    if (before == null) return Future.value(false);
    final wasPublished = before.published;

    return _doctorMutation(
      apply: () {
        for (final r in _reports) {
          if (r.id == id) r.published = true;
        }
      },
      revert: () {
        for (final r in _reports) {
          if (r.id == id) r.published = wasPublished;
        }
      },
      apiCall: () => DoctorApi.instance.publishReport(id),
    );
  }

  Future<bool> updateReport(String id, {String? title, String? body}) {
    ClinicalReport? before;
    for (final r in _reports) {
      if (r.id == id) {
        before = r;
        break;
      }
    }
    if (before == null) return Future.value(false);
    final oldTitle = before.title;
    final oldBody = before.body;

    return _doctorMutation(
      apply: () {
        for (final r in _reports) {
          if (r.id == id) {
            if (title != null) r.title = title;
            if (body != null) r.body = body;
          }
        }
      },
      revert: () {
        for (final r in _reports) {
          if (r.id == id) {
            r.title = oldTitle;
            r.body = oldBody;
          }
        }
      },
      apiCall: () =>
          DoctorApi.instance.updateReport(id, title: title, body: body),
    );
  }

  void setApproval(String id, String status) {
    for (final a in _approvals) {
      if (a.id == id) {
        a.status = status;
        notifyListeners();
        return;
      }
    }
  }

  void setCareRequest(String id, String status) {
    for (final c in _careRequests) {
      if (c.id == id) {
        c.status = status;
        notifyListeners();
        return;
      }
    }
  }

  // The client's vocabulary is approved/rejected — what StaffMapper normalises
  // the API's accepted/declined into, and what every care-request screen
  // filters on. Writing the raw server words here left a doctor's own decision
  // in a state no screen counted until the next session refresh re-mapped it.
  // A doctor never accepts or declines a care request: triage is an admin /
  // mCare-assistant decision, and approving one is what creates the care
  // assignment. The doctor-side accept/decline mutations were removed along
  // with their endpoints — AdminCareRequestsController owns the live path.

  void addAssignment(CareAssignment a) {
    _assignments.insert(0, a);
    notifyListeners();
  }

  void removeAssignment(String id) {
    _assignments.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  /// Persisting variant of [addAssignment]. Calls the admin API; on success
  /// inserts the canonical row.
  // An emergency handover no longer goes through the assignment CRUD. It is
  // one server-side act — see SosResponseApi.handover — because a care-team
  // member is already assigned, so creating a second row could only ever be
  // rejected as a duplicate, and because a care_assignments row on its own
  // never told the receiving provider that an emergency was waiting.

  Future<void> createAssignmentRemote({
    required String patientUserId,
    String? providerId,
    String? providerUserId,
    String? role,
    String? reason,
  }) async {
    if (!AppEnv.backendEnabled) return;
    final dto = await AdminApi.instance.createAssignment(
      patientUserId: patientUserId,
      providerId: providerId,
      providerUserId: providerUserId,
      role: role,
      reason: reason,
    );
    if (dto == null) return;
    _assignments.insert(0, StaffMapper.assignmentFromApi(dto));
    notifyListeners();
  }

  /// Persisting variant of [removeAssignment]. Calls the admin API first;
  /// on success drops the local row. Reverts on API failure.
  Future<void> removeAssignmentRemote(String id, {String? reason}) async {
    final index = _assignments.indexWhere((a) => a.id == id);
    if (index == -1) return;
    final original = _assignments[index];
    _assignments.removeAt(index);
    notifyListeners();
    if (!AppEnv.backendEnabled) return;
    try {
      await AdminApi.instance.removeAssignment(id, reason: reason);
    } catch (e) {
      _assignments.insert(index, original);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> toggleVitalCatalog(String id, bool enabled) async {
    VitalCatalogEntry? entry;
    bool? previous;
    for (final e in _vitalCatalog) {
      if (e.id == id) {
        entry = e;
        previous = e.enabled;
        e.enabled = enabled;
        break;
      }
    }
    if (entry == null) return;
    notifyListeners();

    if (!AppEnv.backendEnabled) return;
    try {
      final raw = await _patchVitalCatalogEntry(id, {'enabled': enabled});
      if (raw != null) {
        _replaceCatalogEntry(StaffMapper.vitalCatalogEntryFromApi(raw));
      }
    } catch (_) {
      entry.enabled = previous ?? entry.enabled;
      notifyListeners();
      rethrow;
    }
  }

  void _replaceCatalogEntry(VitalCatalogEntry updated) {
    final idx = _vitalCatalog.indexWhere((e) => e.id == updated.id);
    if (idx >= 0) {
      _vitalCatalog[idx] = updated;
      notifyListeners();
    }
  }

  bool get _catalogWritesUseDoctorApi =>
      AuthState.instance.user?.role == UserRole.doctor;

  Future<Map<String, dynamic>?> _createVitalCatalogEntryOnServer(
    Map<String, dynamic> body,
  ) {
    if (_catalogWritesUseDoctorApi) {
      return DoctorApi.instance.createVitalCatalogEntry(body);
    }
    return AdminApi.instance.createVitalCatalogEntry(body);
  }

  Future<Map<String, dynamic>?> _patchVitalCatalogEntry(
    String id,
    Map<String, dynamic> body,
  ) {
    if (_catalogWritesUseDoctorApi) {
      return DoctorApi.instance.updateVitalCatalogEntry(id, body);
    }
    return AdminApi.instance.updateVitalCatalogEntry(id, body);
  }

  Future<void> _deleteVitalCatalogEntry(String id) {
    if (_catalogWritesUseDoctorApi) {
      return DoctorApi.instance.deleteVitalCatalogEntry(id);
    }
    return AdminApi.instance.deleteVitalCatalogEntry(id);
  }

  void setUserStatus(String id, String status) {
    for (final u in _users) {
      if (u.id == id) {
        u.status = status;
        notifyListeners();
        return;
      }
    }
  }

  /// Persisting variant of [setUserStatus]. PATCHes the user via AdminApi
  /// then mirrors locally. Reverts on API failure.
  Future<void> setUserStatusRemote(String id, String status) async {
    String? previous;
    for (final u in _users) {
      if (u.id == id) {
        previous = u.status;
        u.status = status;
        break;
      }
    }
    notifyListeners();
    if (!AppEnv.backendEnabled) return;
    try {
      await AdminApi.instance.changeUserStatus(id, status: status);
    } catch (e) {
      if (previous != null) {
        for (final u in _users) {
          if (u.id == id) {
            u.status = previous;
            break;
          }
        }
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Persisting variant for role changes. Reason is required by backend audit.
  Future<void> changeUserRoleRemote(
    String id, {
    required String newRole,
    required String reason,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await AdminApi.instance.changeUserRole(id, role: newRole, reason: reason);
    // Refresh from server-side payload on next list call.
  }

  /// Approve a healthworker via AdminApi. Updates approvals list locally.
  Future<void> approveApplicationRemote(String userId, {String? note}) async {
    if (!AppEnv.backendEnabled) return;
    await AdminApi.instance.approveApplication(userId, note: note);
    for (final a in _approvals) {
      if (a.id == userId) {
        a.status = 'approved';
        break;
      }
    }
    notifyListeners();
  }

  /// Reject a healthworker via AdminApi.
  Future<void> rejectApplicationRemote(
    String userId, {
    required String reason,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await AdminApi.instance.rejectApplication(userId, reason: reason);
    for (final a in _approvals) {
      if (a.id == userId) {
        a.status = 'rejected';
        break;
      }
    }
    notifyListeners();
  }

  /// Route a care request to a provider.
  Future<void> routeCareRequestRemote(
    String requestId, {
    String? providerId,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await AdminApi.instance.routeCareRequest(requestId, providerId: providerId);
  }

  CareRequestItem? careRequestById(String id) {
    for (final r in _careRequests) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Overwrites one care request with the server's canonical row.
  void _replaceCareRequest(CareRequestItem updated) {
    final i = _careRequests.indexWhere((r) => r.id == updated.id);
    if (i == -1) {
      _careRequests.insert(0, updated);
    } else {
      _careRequests[i] = updated;
    }
    notifyListeners();
  }

  /// Applies a decision locally — the mock-mode path, and the optimistic
  /// stand-in until the server row arrives.
  void _applyCareRequestDecision(
    String id,
    String status, {
    String? note,
    String? assignedProviderId,
    String? assignedProviderName,
    String? role,
  }) {
    final request = careRequestById(id);
    if (request == null) return;
    request.status = status;
    request.decisionNote = note;
    request.decidedAt = DateTime.now();
    request.decidedByName = AuthState.instance.user?.fullName;
    if (assignedProviderId != null) {
      request.assignedProviderId = assignedProviderId;
    }
    if (assignedProviderName != null) {
      request.assignedProviderName = assignedProviderName;
      request.reassigned =
          assignedProviderName.trim() != request.providerRequested.trim();
    }
    if (role != null) request.assignmentRole = role;
    notifyListeners();
  }

  /// Admin: approve a pending care request. Passing a provider other than the
  /// requested one re-routes the patient — the backend then requires [note].
  ///
  /// On success the matching care assignment exists server-side, so the local
  /// assignment list is refreshed too. Throws on API failure so the caller can
  /// surface the server's message.
  Future<void> approveCareRequestAdminRemote(
    String id, {
    String? providerId,
    String? providerUserId,
    String? role,
    String? note,
    String? providerName,
  }) async {
    if (!AppEnv.backendEnabled) {
      _applyCareRequestDecision(
        id,
        'approved',
        note: note,
        assignedProviderId: providerId,
        assignedProviderName: providerName,
        role: role,
      );
      _addLocalAssignmentForRequest(id, role: role, note: note);
      return;
    }

    final dto = await AdminApi.instance.routeCareRequest(
      id,
      providerId: providerId,
      providerUserId: providerUserId,
      role: role,
      note: note,
    );
    if (dto != null) {
      _replaceCareRequest(StaffMapper.careRequestFromApi(dto));
    } else {
      _applyCareRequestDecision(id, 'approved', note: note, role: role);
    }
    await refreshAssignments();
  }

  /// Admin: decline a pending care request. The reason reaches the patient.
  Future<void> rejectCareRequestAdminRemote(
    String id, {
    required String reason,
  }) async {
    if (!AppEnv.backendEnabled) {
      _applyCareRequestDecision(id, 'rejected', note: reason);
      return;
    }
    final dto = await AdminApi.instance.cancelCareRequest(id, reason: reason);
    if (dto != null) {
      _replaceCareRequest(StaffMapper.careRequestFromApi(dto));
    } else {
      _applyCareRequestDecision(id, 'rejected', note: reason);
    }
  }

  /// Re-reads the assignment list from the API. No-op in mock mode, where the
  /// seeded rows are the source of truth.
  Future<void> refreshAssignments() async {
    if (!AppEnv.backendEnabled) return;
    final rows = await AdminApi.instance.listAssignments();
    mergeAssignments(
      rows.map((e) => StaffMapper.assignmentFromApi(e)).toList(),
    );
  }

  /// Mock-mode mirror of the server-side "approve ⇒ assign" rule.
  void _addLocalAssignmentForRequest(
    String requestId, {
    String? role,
    String? note,
  }) {
    final request = careRequestById(requestId);
    if (request == null) return;
    final provider = request.effectiveProvider;
    final already = _assignments.any(
      (a) => a.patient == request.patient && a.provider == provider,
    );
    if (already) return;
    _assignments.insert(
      0,
      CareAssignment(
        id: 'as_${DateTime.now().millisecondsSinceEpoch}',
        patient: request.patient,
        provider: provider,
        assignedAt: DateTime.now(),
        role: role ?? 'Primary',
        patientId: request.patientId,
        providerId: request.assignedProviderId ?? request.providerId,
        assignedReason: note,
      ),
    );
    notifyListeners();
  }

  void toggleSystem(int index, bool value) {
    if (index < 0 || index >= _system.length) return;
    _system[index].value = value;
    notifyListeners();
  }

  void toggleSystemByKey(String key, bool value) {
    final item = _system.where((s) => s.key == key).firstOrNull;
    if (item == null) return;
    item.value = value;
    notifyListeners();
  }

  void addAudit(AuditEntry entry) {
    _audit.insert(0, entry);
    notifyListeners();
  }

  /// Clinician chart edit. Updates the slim `StaffPatient` row optimistically
  /// (condition/sex/age/risk) and PATCHes the full health profile via
  /// `DoctorApi.updatePatientChart`. In mock mode (backend disabled) the
  /// audit + notification are written locally; with the backend on they
  /// arrive on the next session sync.
  ///
  /// Returns the list of changed labels, or empty if nothing changed /
  /// the API call failed.
  Future<List<String>> updatePatientChart({
    required String patientId,
    required String actor,
    String? condition,
    String? sex,
    int? age,
    RiskLevel? risk,
    Map<String, dynamic>? healthDelta,
    String? note,
  }) async {
    final p = patientById(patientId);
    if (p == null) return const [];

    // Capture original values for revert on API failure.
    final beforeCondition = p.condition;
    final beforeSex = p.sex;
    final beforeAge = p.age;
    final beforeRisk = p.risk;

    final changes = <String>[];
    if (condition != null &&
        condition.trim().isNotEmpty &&
        condition.trim() != p.condition) {
      p.condition = condition.trim();
      changes.add('Condition');
    }
    if (sex != null && sex.trim().isNotEmpty && sex.trim() != p.sex) {
      p.sex = sex.trim();
      changes.add('Sex');
    }
    if (age != null && age > 0 && age != p.age) {
      p.age = age;
      changes.add('Age');
    }
    if (risk != null && risk != p.risk) {
      p.risk = risk;
      changes.add('Risk');
    }
    if (changes.isEmpty && (healthDelta == null || healthDelta.isEmpty)) {
      return const [];
    }

    notifyListeners();

    if (!AppEnv.backendEnabled) {
      // Mock mode — write audit + notification locally.
      _audit.insert(
        0,
        AuditEntry(
          id: 'chart_${DateTime.now().millisecondsSinceEpoch}',
          at: DateTime.now(),
          actor: actor,
          action: 'Updated chart: ${changes.join(', ')}',
          target: p.name,
        ),
      );
      notifyListeners();
      return changes;
    }

    try {
      final apiChanges = await DoctorApi.instance.updatePatientChart(
        patientUserId: patientId,
        healthDelta: healthDelta ?? const {},
        note: note,
      );
      // Server's authoritative change list (may include health fields the
      // server detected and the slim row didn't track).
      if (apiChanges.isNotEmpty) {
        for (final l in apiChanges) {
          if (!changes.contains(l)) changes.add(l);
        }
      }
      return changes;
    } catch (_) {
      // Revert optimistic changes on failure.
      p.condition = beforeCondition;
      p.sex = beforeSex;
      p.age = beforeAge;
      p.risk = beforeRisk;
      notifyListeners();
      return const [];
    }
  }
}

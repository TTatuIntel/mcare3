import '../../shared/models/meal_plan.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/document.dart';
import '../../shared/state/staff_state.dart';
import '../../shared/vitals/vital_alert_parse.dart';
import 'patient_domain_mapper.dart';
import 'patient_profile_mapper.dart';

/// Maps doctor / staff API payloads → in-memory `StaffState` models.
/// One-direction only — staff-side mutations don't round-trip via
/// these models; the API returns updated rows that we re-seed in place.
class StaffMapper {
  StaffMapper._();

  // ---------------------------------------------------------------------------
  // Caseload / patients
  // ---------------------------------------------------------------------------
  static StaffPatient patientFromApi(Map<String, dynamic> j) => StaffPatient(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '') as String,
    age: (j['age'] as num?)?.toInt() ?? 0,
    sex: (j['sex'] as String?) ?? '—',
    condition: (j['condition'] as String?) ?? '',
    risk: _risk(j['risk'] as String?),
    lastReading: _parseDate(j['last_reading_at']) ?? DateTime.now(),
    assignedDoctor: (j['assigned_doctor'] as String?) ?? '',
    unreadAlerts: (j['unread_alerts'] as num?)?.toInt() ?? 0,
  );

  // ---------------------------------------------------------------------------
  // Alerts (sourced from AppNotification kinds vital_warning/critical/sos)
  // ---------------------------------------------------------------------------
  static StaffAlert alertFromApi(Map<String, dynamic> j) {
    final kind = j['kind'] as String?;
    final vitalKey = j['vital_key'] as String?;
    final title = j['title'] as String?;
    final body = j['body'] as String?;
    final value = (j['value'] as String?) ?? body ?? '';

    return StaffAlert(
        id: (j['id'] ?? '').toString(),
        patientId: (j['patient_id'] ?? '').toString(),
        patientName: (j['patient_name'] ?? '') as String,
        vital: parseVitalFromAlertPayload(
          vitalKey: vitalKey,
          title: title,
          body: body,
          kind: kind,
        ),
        value: value,
        severity: severityFromAlertKind(kind, j['severity'] as String?),
        createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
        kind: kind,
        acknowledged: (j['acknowledged'] as bool?) ?? false,
      )
      ..resolved = (j['resolved'] as bool?) ?? false
      ..resolutionNote = j['resolution_note'] as String?
      ..resolutionAction = j['resolution_action'] as String?
      ..resolutionCustomAction = j['resolution_custom_action'] as String?
      ..resolvedBy = j['resolved_by'] as String?
      ..acknowledgedBy = j['acknowledged_by'] as String?;
  }

  // ---------------------------------------------------------------------------
  // Appointments
  // ---------------------------------------------------------------------------
  static StaffAppointment appointmentFromApi(Map<String, dynamic> j) =>
      StaffAppointment(
        id: (j['id'] ?? '').toString(),
        patientId: (j['patient_id'] ?? '').toString(),
        patientName: (j['patient_name'] ?? '') as String,
        startAt: _parseDate(j['scheduled_at']) ?? DateTime.now(),
        type: _appointmentTypeFromApi(j['type'] as String?),
        reason: (j['reason'] as String?) ?? (j['notes'] as String?),
        status: _appointmentStatusFromApi(j['status'] as String?),
        durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 30,
        locationOrLink: j['location_or_link'] as String?,
        cancellationReason: j['cancellation_reason'] as String?,
      );

  static AppointmentType _appointmentTypeFromApi(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'virtual':
        return AppointmentType.virtual;
      case 'phone':
        return AppointmentType.phone;
      default:
        return AppointmentType.inPerson;
    }
  }

  static AppointmentStatus _appointmentStatusFromApi(String? raw) {
    return AppointmentStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => AppointmentStatus.scheduled,
    );
  }

  // ---------------------------------------------------------------------------
  // Prescriptions
  // ---------------------------------------------------------------------------
  static StaffPrescription prescriptionFromApi(Map<String, dynamic> j) =>
      StaffPrescription(
        id: (j['id'] ?? '').toString(),
        patientId: (j['patient_id'] ?? '').toString(),
        patientName: (j['patient_name'] ?? '') as String,
        drug: (j['drug'] ?? '') as String,
        dosage: (j['dosage'] ?? '') as String,
        frequency: (j['frequency'] ?? '') as String,
        duration: _durationLabel(
          j['start_date'] as String?,
          j['end_date'] as String?,
        ),
        issuedAt: _parseDate(j['start_date']) ?? DateTime.now(),
        status: (j['status'] as String?) ?? 'Active',
      );

  // ---------------------------------------------------------------------------
  // Clinical reports
  // ---------------------------------------------------------------------------
  static ClinicalReport reportFromApi(Map<String, dynamic> j) => ClinicalReport(
    id: (j['id'] ?? '').toString(),
    patientName: (j['patient_name'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    body: (j['body'] ?? '') as String,
    createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
    published: (j['published'] as bool?) ?? false,
  );

  // ---------------------------------------------------------------------------
  // Pending vital-report requests + care requests
  // ---------------------------------------------------------------------------
  static StaffPatientRequest vitalReportRequestFromApi(
    Map<String, dynamic> j,
  ) => StaffPatientRequest(
    id: (j['id'] ?? '').toString(),
    patientId: (j['patient_id'] ?? '').toString(),
    type: 'Vital report',
    summary: (j['note'] as String?)?.isNotEmpty == true
        ? j['note'] as String
        : 'Vital summary report',
    status: (j['status'] as String?) ?? 'pending',
    createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
  );

  static CareRequestItem careRequestFromApi(
    Map<String, dynamic> j,
  ) => CareRequestItem(
    id: (j['id'] ?? '').toString(),
    patient: (j['patient_name'] ?? '') as String,
    providerRequested: (j['provider_name'] ?? '') as String,
    reason: (j['reason'] ?? '') as String,
    createdAt: _parseDate(j['created_at']) ?? DateTime.now(),
    // The admin list endpoint sends patient_user_id; session sends patient_id.
    patientId: (j['patient_id'] ?? j['patient_user_id'])?.toString(),
    status: _normalizeCareRequestStatus((j['status'] as String?) ?? 'pending'),
    providerId: j['provider_id']?.toString(),
    providerSpecialty: j['provider_specialty'] as String?,
    assignedProviderId: j['assigned_provider_id']?.toString(),
    assignedProviderName: j['assigned_provider_name'] as String?,
    assignmentRole: j['assignment_role'] as String?,
    decisionNote: j['decision_note'] as String?,
    decidedAt: _parseDate(j['decided_at']),
    decidedByName: j['decided_by_name'] as String?,
    reassigned: j['reassigned'] as bool? ?? false,
  );

  static String _normalizeCareRequestStatus(String s) {
    if (s == 'cancelled' || s == 'canceled' || s == 'declined')
      return 'rejected';
    if (s == 'accepted') return 'approved';
    return s;
  }

  // ---------------------------------------------------------------------------
  // Doctor profile shorthand
  // ---------------------------------------------------------------------------
  static DirectoryUser directoryUserFromApi(Map<String, dynamic> j) =>
      DirectoryUser(
        id: (j['id'] ?? '').toString(),
        uniqueId: (j['unique_id'] ?? '') as String,
        name: '${j['first_name'] ?? ''} ${j['last_name'] ?? ''}'.trim(),
        email: (j['email'] ?? '') as String,
        role: _role(j['role'] as String?),
        status: 'active',
        joinedAt: DateTime.now(),
        isLocked: j['is_locked'] as bool? ?? false,
        lockedUntil: _parseDate(j['locked_until']),
        mustChangePassword: j['must_change_password'] as bool? ?? false,
      );

  /// Full variant used by the admin users list — preserves status and joined date
  /// from the API payload.
  static DirectoryUser directoryUserFromApiFull(Map<String, dynamic> j) =>
      DirectoryUser(
        id: (j['id'] ?? '').toString(),
        uniqueId: (j['unique_id'] ?? '') as String,
        name: '${j['first_name'] ?? ''} ${j['last_name'] ?? ''}'.trim(),
        email: (j['email'] ?? '') as String,
        role: _role(j['role'] as String?),
        status: _normalizeUserStatus(
          (j['approval_status'] as String?) ?? (j['status'] as String?),
        ),
        joinedAt: _parseDate(j['created_at']) ?? DateTime.now(),
        specialty: j['specialty'] as String?,
        licenseNumber: j['license_number'] as String?,
        isLocked: j['is_locked'] as bool? ?? false,
        lockedUntil: _parseDate(j['locked_until']),
        mustChangePassword: j['must_change_password'] as bool? ?? false,
      );

  static String _normalizeUserStatus(String? raw) {
    if (raw == null || raw.isEmpty) return 'active';
    return switch (raw) {
      'pendingApproval' || 'pending_approval' => 'pending',
      _ => raw,
    };
  }

  // ---------------------------------------------------------------------------
  // Admin directory — approvals, assignments, audit, system settings
  // ---------------------------------------------------------------------------
  static HealthworkerApproval approvalFromApi(Map<String, dynamic> j) =>
      HealthworkerApproval(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        specialty: (j['specialty'] as String?)?.trim().isNotEmpty == true
            ? (j['specialty'] as String).trim()
            : _approvalSpecialty(j['role'] as String?),
        licenseNumber: j['license_number'] as String?,
        appliedAt: _parseDate(j['submitted_at']) ?? DateTime.now(),
        status: _normalizeApprovalStatus((j['status'] as String?) ?? 'pending'),
        hasCredentialDocument: j['has_credential_document'] as bool? ?? false,
        credentialDocumentName: j['credential_document_name'] as String?,
      );

  static String _normalizeApprovalStatus(String s) {
    if (s == 'pendingApproval' || s == 'pending_approval') return 'pending';
    return s;
  }

  static String _approvalSpecialty(String? role) {
    return switch (role) {
      'doctor' || 'Doctor' => 'Doctor',
      'mcareAssistant' || 'mcare_assistant' => 'mCare Assistant',
      _ => role ?? 'Doctor',
    };
  }

  static CareAssignment assignmentFromApi(Map<String, dynamic> j) =>
      CareAssignment(
        id: (j['id'] ?? '').toString(),
        patient: (j['patient_name'] ?? '') as String,
        provider: (j['provider_name'] ?? '') as String,
        role: (j['role'] as String?) ?? 'Primary',
        assignedAt: _parseDate(j['assigned_at']) ?? DateTime.now(),
        patientId: (j['patient_user_id'] ?? j['patient_id'])?.toString(),
        providerId: j['provider_id']?.toString(),
        providerUserId: j['provider_user_id']?.toString(),
        providerSpecialty: j['provider_specialty'] as String?,
        assignedReason: j['assigned_reason'] as String?,
        assignedByName: j['assigned_by_name'] as String?,
      );

  static AuditEntry auditFromApi(Map<String, dynamic> j) => AuditEntry(
    id: (j['id'] ?? '').toString(),
    at: _parseDate(j['happened_at']) ?? DateTime.now(),
    actor: (j['actor'] ?? '') as String,
    action: (j['action'] ?? '') as String,
    target: (j['target'] ?? '') as String,
    category: (j['category'] as String?) ?? 'activity',
  );

  static SystemConfigSection systemSettingFromApi(Map<String, dynamic> j) =>
      SystemConfigSection(
        key: (j['key'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        category: (j['category'] as String?) ?? 'Runtime',
        value: (j['value'] as bool?) ?? false,
      );

  // ---------------------------------------------------------------------------
  // Per-patient workspace detail (from GET /doctor/patients/{id})
  // ---------------------------------------------------------------------------
  static StaffPatientDocument documentFromApi(
    Map<String, dynamic> j, {
    required String patientId,
  }) => StaffPatientDocument(
    id: (j['id'] ?? '').toString(),
    patientId: patientId,
    title: (j['title'] ?? j['name'] ?? 'Document') as String,
    category: (j['category'] ?? j['type'] ?? 'General') as String,
    uploadedAt:
        _parseDate(j['uploaded_at'] ?? j['created_at']) ?? DateTime.now(),
    uploadedBy: (j['uploaded_by'] as String?) ?? 'Patient',
    fileType: PatientDomainMapper.documentFileTypeFromApi(
      j['file_type'] as String?,
    ),
    description: j['description'] as String?,
    hasFile: j['has_file'] as bool? ?? true,
    source: switch (j['source'] as String?) {
      'clinician' => DocumentSource.clinician,
      'report' => DocumentSource.report,
      _ => DocumentSource.patient,
    },
    removalRequested: j['removal_requested'] == true,
    removalReason: j['removal_reason'] as String?,
  );

  static StaffPatientSos sosFromApi(
    Map<String, dynamic> j, {
    required String patientId,
  }) => StaffPatientSos(
    id: (j['id'] ?? '').toString(),
    patientId: (j['patient_id'] ?? patientId).toString(),
    patientName: j['patient_name'] as String?,
    kind: (j['kind'] as String?) ?? 'other',
    status: (j['status'] as String?) ?? 'active',
    triggeredAt: _parseDate(j['triggered_at']) ?? DateTime.now(),
    locationLabel: j['location_label'] as String?,
    note: j['note'] as String?,
    latitude: (j['latitude'] as num?)?.toDouble(),
    longitude: (j['longitude'] as num?)?.toDouble(),
    respondedBy: j['responded_by'] as String?,
    respondedAt: _parseDate(j['responded_at']),
    resolution: j['resolution'] as String?,
    resolutionLabel: j['resolution_label'] as String?,
    resolutionNote: j['resolution_note'] as String?,
    progress: sosProgressFromApi(j['response_actions']),
  );

  /// The response trail that rides along with an SOS payload. Oldest first —
  /// the order the work happened in.
  static List<SosProgressStep> sosProgressFromApi(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) {
      final m = e.cast<String, dynamic>();
      return SosProgressStep(
        action: (m['action'] ?? '').toString(),
        label: (m['label'] ?? 'Step').toString(),
        actorName: (m['actor_name'] ?? '').toString(),
        at: _parseDate(m['created_at']) ?? DateTime.now(),
        detail: m['detail'] as String?,
      );
    }).toList();
  }

  static StaffPatientVitalReading vitalReadingFromApi(
    Map<String, dynamic> j, {
    required String patientId,
  }) {
    final vitalKey =
        (j['vital'] ?? j['vital_key'] ?? 'bloodPressure') as String;

    return StaffPatientVitalReading(
      id: j['id']?.toString(),
      patientId: (j['patient_id'] ?? patientId).toString(),
      patientName: j['patient_name'] as String?,
      vital: PatientProfileMapper.vitalKeyFromApi(vitalKey),
      value: _vitalDisplayValue(j, vitalKey),
      risk: _risk(j['risk'] as String?),
      recordedAt: _parseDate(j['recorded_at']) ?? DateTime.now(),
      note: j['note'] as String?,
    );
  }

  static String _vitalDisplayValue(Map<String, dynamic> j, String vitalKey) {
    final display = j['display_value'];
    if (display is String && display.trim().isNotEmpty) return display;

    final value = j['value'];
    final secondary = j['secondary_value'];
    if (vitalKey == 'bloodPressure' && value != null && secondary != null) {
      final sys = (value as num).round();
      final dia = (secondary as num).round();
      return '$sys/$dia mmHg';
    }

    if (value == null) return '';

    final vital = PatientProfileMapper.vitalKeyFromApi(vitalKey);
    final formatted = vitalKey == 'temperature' || vitalKey == 'weight'
        ? (value as num).toStringAsFixed(1)
        : '${(value as num).round()}';
    final unit = vital.unit;
    return unit.isNotEmpty ? '$formatted $unit' : formatted;
  }

  // ---------------------------------------------------------------------------
  // Meal plans
  // ---------------------------------------------------------------------------
  static StaffMealPlan mealPlanFromApi(Map<String, dynamic> j) => StaffMealPlan(
    id: (j['id'] ?? '').toString(),
    patientId: (j['patient_id'] ?? '').toString(),
    patientName: (j['patient_name'] ?? '') as String,
    title: (j['title'] ?? '') as String,
    mealType: _mealTypeFromApi(j['meal_type'] as String?),
    description: j['description'] as String?,
    calories: (j['calories'] as num?)?.toInt(),
    protein: j['protein'] as String?,
    carbs: j['carbs'] as String?,
    fat: j['fat'] as String?,
    notes: j['notes'] as String?,
    assignedAt:
        _parseDate(j['assigned_at'] ?? j['created_at']) ?? DateTime.now(),
    assignedBy: (j['assigned_by'] as String?) ?? '',
  );

  static MealType _mealTypeFromApi(String? raw) => MealType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => MealType.general,
  );

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  static RiskLevel _risk(String? s) => switch (s) {
    'critical' => RiskLevel.critical,
    'warning' => RiskLevel.warning,
    'normal' => RiskLevel.normal,
    _ => RiskLevel.unknown,
  };

  static UserRole _role(String? s) => switch (s) {
    'doctor' => UserRole.doctor,
    'admin' => UserRole.admin,
    'mcareAssistant' || 'mcare_assistant' => UserRole.mcareAssistant,
    _ => UserRole.patient,
  };

  static DateTime? _parseDate(dynamic v) {
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  static String _durationLabel(String? from, String? to) {
    final start = _parseDate(from);
    final end = _parseDate(to);
    if (start == null || end == null) return 'Ongoing';
    final days = end.difference(start).inDays;
    return '$days days';
  }

  static VitalCatalogEntry vitalCatalogEntryFromApi(Map<String, dynamic> j) {
    final keyRaw = (j['vital'] ?? j['vital_key'] ?? '') as String;
    // Only map to a built-in VitalKey when the API key is a known enum name.
    final isBuiltin = VitalKey.values.any((v) => v.name == keyRaw);
    final vitalKey = isBuiltin
        ? PatientProfileMapper.vitalKeyFromApi(keyRaw)
        : null;
    final customLabel = j['custom_label'] as String?;
    final id = (j['id'] as String?) ?? vitalKey?.name ?? keyRaw;

    VitalAlertConfig? alertConfig;
    if (j['alert_config'] is Map) {
      final ac = (j['alert_config'] as Map).cast<String, dynamic>();
      alertConfig = VitalAlertConfig(
        enableWarningAlerts: ac['enable_warning_alerts'] as bool? ?? true,
        enableCriticalAlerts: ac['enable_critical_alerts'] as bool? ?? true,
        autoResolveOnNormal: ac['auto_resolve_on_normal'] as bool? ?? true,
        escalationEnabled: ac['escalation_enabled'] as bool? ?? false,
        escalationDelayMinutes:
            (ac['escalation_delay_minutes'] as num?)?.toInt() ?? 60,
        criticalAlertTitle: ac['critical_alert_title'] as String?,
        warningAlertTitle: ac['warning_alert_title'] as String?,
      );
    }

    return VitalCatalogEntry(
      id: id,
      vital: vitalKey,
      customLabel: customLabel,
      customUnit: j['custom_unit'] as String?,
      description: j['description'] as String?,
      normalMin: (j['normal_min'] as num).toDouble(),
      normalMax: (j['normal_max'] as num).toDouble(),
      warningLow: (j['warning_low'] as num).toDouble(),
      warningHigh: (j['warning_high'] as num).toDouble(),
      criticalLow: (j['critical_low'] as num).toDouble(),
      criticalHigh: (j['critical_high'] as num).toDouble(),
      enabled: j['enabled'] as bool? ?? true,
      alertConfig: alertConfig,
      createdBy: (j['created_by'] as String?) ?? 'system',
      createdAt: j['created_at'] != null
          ? DateTime.tryParse(j['created_at'] as String) ?? DateTime(2024)
          : DateTime(2024),
      updatedBy: j['updated_by'] as String?,
      updatedAt: j['updated_at'] != null
          ? DateTime.tryParse(j['updated_at'] as String)
          : null,
    );
  }
}

/// One tickable section in the patient-report builder.
///
/// Sensitivity is decided by the backend. Confidentiality changes how a section
/// is labelled; it does NOT introduce a patient-consent/permission gate.
class ReportSectionOption {
  const ReportSectionOption({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
    required this.confidential,
    required this.clinical,
  });

  final String key;
  final String label;
  final String description;

  /// Personal / Account / Care / Clinical — how the tick-list is grouped.
  final String group;

  /// True when the section carries sensitive clinical or identifying detail.
  /// This is display/risk metadata only and never blocks report creation.
  final bool confidential;

  /// Clinical metadata retained for section classification. The report workflow
  /// still requires a doctor signature for every report, not only clinical ones.
  final bool clinical;

  static ReportSectionOption fromJson(Map<String, dynamic> j) {
    return ReportSectionOption(
      key: '${j['key'] ?? ''}',
      label: '${j['label'] ?? ''}',
      description: '${j['description'] ?? ''}',
      group: '${j['group'] ?? 'Other'}',
      confidential: j['confidential'] == true,
      clinical: j['clinical'] == true,
    );
  }
}

/// Lifecycle of a customised patient report.
///
/// Active workflow:
/// 1. Admin creates the report request.
/// 2. Doctor reviews and signs (or declines).
/// 3. Signed report returns to the admin queue.
/// 4. Admin approves/issues it.
/// 5. Issued report becomes visible to the patient.
/// 6. Only the patient may delete their own issued document.
///
/// There is no patient-consent step.
class PatientReportRequestItem {
  const PatientReportRequestItem({
    required this.id,
    required this.patientId,
    required this.title,
    required this.purpose,
    required this.status,
    required this.statusLabel,
    required this.sections,
    required this.sectionLabels,
    this.patientName,
    this.patientUniqueId,
    this.requestedByName,
    this.doctorId,
    this.doctorName,
    this.recipient,
    this.signatureRequired = true,
    this.blockedOn,
    this.declinedAt,
    this.declineReason,
    this.signedAt,
    this.signatureName,
    this.signatureNote,
    this.awaitingIssueDecision = false,
    this.awaitingRework = false,
    this.returnedAt,
    this.returnedByName,
    this.returnNote,
    this.returnCount = 0,
    this.underReview = false,
    this.underReviewAt,
    this.underReviewNote,
    this.issuedAt,
    this.revokedAt,
    this.revokeReason,
    this.createdAt,
    this.awaitingMe = false,
    this.canOpenDocument = false,
    this.sectionDetails = const [],

    // Legacy compatibility fields. They do not gate anything.
    this.consentRequired = false,
    this.consentSentAt,
    this.consentExpiresAt,
    this.consentExpired = false,
    this.consentAttempts = 0,
    this.consentedAt,
    this.consentMethod,
  });

  final String id;
  final String patientId;
  final String? patientName;
  final String? patientUniqueId;
  final String? requestedByName;
  final String? doctorId;
  final String? doctorName;

  final String title;
  final String purpose;
  final String? recipient;
  final List<String> sections;
  final List<String> sectionLabels;

  /// Every report in the new workflow requires a doctor signature.
  final bool signatureRequired;

  /// draft / pending_signature / signed / declined / issued / revoked
  final String status;
  final String statusLabel;

  /// doctor_signature, issue, or null when no further workflow action is due.
  final String? blockedOn;

  final DateTime? declinedAt;
  final String? declineReason;

  final DateTime? signedAt;
  final String? signatureName;
  final String? signatureNote;

  /// Signed, not yet issued — waiting for admin approval/share.
  final bool awaitingIssueDecision;

  /// Sent back to the doctor and not yet re-signed.
  final bool awaitingRework;

  final DateTime? returnedAt;
  final String? returnedByName;
  final String? returnNote;
  final int returnCount;

  /// An admin has opened/read the signed report but has not yet issued it.
  final bool underReview;
  final DateTime? underReviewAt;
  final String? underReviewNote;

  final DateTime? issuedAt;
  final DateTime? revokedAt;
  final String? revokeReason;
  final DateTime? createdAt;

  /// Server-set flag indicating that this row needs the current user's action.
  final bool awaitingMe;

  /// True only when the authenticated user is allowed to open the finished
  /// report document. For patients this should become true after admin issue.
  final bool canOpenDocument;

  /// Patient-facing plain-language section descriptions.
  final List<Map<String, dynamic>> sectionDetails;

  // ---------------------------------------------------------------------------
  // Legacy consent properties retained to avoid breaking older screens/models.
  // They are informational only. `consentRequired` is always false when parsed.
  // ---------------------------------------------------------------------------
  final bool consentRequired;
  final DateTime? consentSentAt;
  final DateTime? consentExpiresAt;
  final bool consentExpired;
  final int consentAttempts;
  final DateTime? consentedAt;
  final String? consentMethod;

  bool get isIssued => status == 'issued';

  bool get isSigned =>
      status == 'signed' || signedAt != null || signatureName != null;

  bool get isClosed =>
      status == 'issued' || status == 'revoked' || status == 'declined';

  bool get awaitingSignature =>
      status == 'pending_signature' || blockedOn == 'doctor_signature';

  /// A signed report that is waiting for the admin's final decision.
  bool get readyToIssue =>
      status == 'signed' || blockedOn == 'issue' || awaitingIssueDecision;

  /// Patient-owned deletion should only be offered for a document that has
  /// actually been issued/shared to the patient.
  bool get canPatientDelete => isIssued && canOpenDocument;

  static PatientReportRequestItem fromJson(Map<String, dynamic> j) {
    final signedAt = _date(j['signed_at']);
    final signatureName = _str(j['signature_name']);

    final rawStatus = '${j['status'] ?? 'draft'}';
    final status = _normaliseLegacyStatus(
      rawStatus,
      signed: signedAt != null || signatureName != null,
    );

    final blockedOn = _normaliseBlockedOn(
      _str(j['blocked_on']),
      status: status,
      signed: signedAt != null || signatureName != null,
    );

    final serverAwaitingIssue = j['awaiting_issue_decision'] == true;
    final readyForAdmin =
        status == 'signed' || blockedOn == 'issue' || serverAwaitingIssue;

    return PatientReportRequestItem(
      id: '${j['id'] ?? ''}',
      patientId: '${j['patient_id'] ?? ''}',
      patientName: _str(j['patient_name']),
      patientUniqueId: _str(j['patient_unique_id']),
      requestedByName: _str(j['requested_by_name']),
      doctorId: _str(j['doctor_id']),
      doctorName: _str(j['doctor_name']),
      title: '${j['title'] ?? ''}',
      purpose: '${j['purpose'] ?? ''}',
      recipient: _str(j['recipient']),
      sections: _strings(j['sections']),
      sectionLabels: _strings(j['section_labels']),

      // Do not let legacy backend consent flags reintroduce a client-side gate.
      consentRequired: false,

      // Doctor signature is mandatory in the new workflow. Only an explicit
      // false from a newer backend is respected for backwards compatibility.
      signatureRequired: j['signature_required'] != false,
      status: status,
      statusLabel: _statusLabel(j['status_label'], status),
      blockedOn: blockedOn,
      declinedAt: _date(j['declined_at']),
      declineReason: _str(j['decline_reason']),
      signedAt: signedAt,
      signatureName: signatureName,
      signatureNote: _str(j['signature_note']),
      awaitingIssueDecision: readyForAdmin,
      awaitingRework: j['awaiting_rework'] == true,
      returnedAt: _date(j['returned_at']),
      returnedByName: _str(j['returned_by_name']),
      returnNote: _str(j['return_note']),
      returnCount: _int(j['return_count']) ?? 0,
      underReview: j['under_review'] == true,
      underReviewAt: _date(j['under_review_at']),
      underReviewNote: _str(j['under_review_note']),
      issuedAt: _date(j['issued_at']),
      canOpenDocument: j['can_open_document'] == true,
      revokedAt: _date(j['revoked_at']),
      revokeReason: _str(j['revoke_reason']),
      createdAt: _date(j['created_at']),
      awaitingMe: j['awaiting_me'] == true,
      sectionDetails: j['section_details'] is List
          ? (j['section_details'] as List)
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList()
          : const [],

      // Keep historical metadata available for audit/old UI, but never gate on it.
      consentSentAt: _date(j['consent_sent_at']),
      consentExpiresAt: _date(j['consent_expires_at']),
      consentExpired: false,
      consentAttempts: _int(j['consent_attempts']) ?? 0,
      consentedAt: _date(j['consented_at']),
      consentMethod: _str(j['consent_method']),
    );
  }
}

/// The assembled report body.
///
/// Patient consent metadata is retained only as optional legacy/audit data.
/// It does not control creation, signing, admin approval, issue, or visibility.
class PatientReportDocument {
  const PatientReportDocument({
    required this.title,
    required this.sections,
    this.purpose,
    this.recipient,
    this.patientName,
    this.patientUniqueId,
    this.generatedAt,
    this.preparedBy,
    this.signedAt,
    this.signatureName,
    this.signatureNote,
    this.consentGrantedAt,
    this.consentMethod,
  });

  final String title;
  final String? purpose;
  final String? recipient;
  final String? patientName;
  final String? patientUniqueId;
  final DateTime? generatedAt;
  final String? preparedBy;

  final DateTime? signedAt;
  final String? signatureName;
  final String? signatureNote;
  final List<ReportBlock> sections;

  // Legacy/audit-only fields.
  final DateTime? consentGrantedAt;
  final String? consentMethod;

  static PatientReportDocument fromJson(Map<String, dynamic> j) {
    final signature = j['signature'] is Map
        ? (j['signature'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    final consent = j['consent'] is Map
        ? (j['consent'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return PatientReportDocument(
      title: '${j['title'] ?? 'Patient report'}',
      purpose: _str(j['purpose']),
      recipient: _str(j['recipient']),
      patientName: _str(j['patient_name']),
      patientUniqueId: _str(j['patient_unique_id']),
      generatedAt: _date(j['generated_at']),
      preparedBy: _str(j['prepared_by']),
      signedAt: _date(signature['signed_at'] ?? j['signed_at']),
      signatureName: _str(signature['name'] ?? j['signature_name']),
      signatureNote: _str(signature['note'] ?? j['signature_note']),
      consentGrantedAt: _date(consent['granted_at']),
      consentMethod: _str(consent['method']),
      sections: (j['sections'] is List ? j['sections'] as List : const [])
          .whereType<Map>()
          .map((e) => ReportBlock.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// One rendered block: a field list, a table, or free-text notes.
class ReportBlock {
  const ReportBlock({
    required this.key,
    required this.title,
    required this.kind,
    this.fields = const [],
    this.columns = const [],
    this.rows = const [],
    this.notes = const [],
    this.emptyMessage = 'Nothing recorded.',
  });

  final String key;
  final String title;

  /// fields / table / notes
  final String kind;

  final List<({String label, String value})> fields;
  final List<String> columns;
  final List<List<String>> rows;
  final List<Map<String, String>> notes;
  final String emptyMessage;

  bool get isEmpty => switch (kind) {
        'table' => rows.isEmpty,
        'notes' => notes.isEmpty,
        _ => fields.isEmpty,
      };

  static ReportBlock fromJson(Map<String, dynamic> j) {
    final kind = '${j['kind'] ?? 'fields'}';

    return ReportBlock(
      key: '${j['key'] ?? ''}',
      title: '${j['title'] ?? ''}',
      kind: kind,
      fields: (j['rows'] is List && kind == 'fields')
          ? (j['rows'] as List)
              .whereType<Map>()
              .map(
                (e) => (
                  label: '${e['label'] ?? ''}',
                  value: '${e['value'] ?? ''}',
                ),
              )
              .toList()
          : const [],
      columns: _strings(j['columns']),
      rows: (j['rows'] is List && kind == 'table')
          ? (j['rows'] as List)
              .whereType<List>()
              .map((r) => r.map((c) => '${c ?? ''}').toList())
              .toList()
          : const [],
      notes: (j['notes'] is List)
          ? (j['notes'] as List)
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry('$k', '${v ?? ''}')))
              .toList()
          : const [],
      emptyMessage: '${j['empty_message'] ?? 'Nothing recorded.'}',
    );
  }
}

// --------------------------- parsing helpers ---------------------------

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : const [];

String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

int? _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

String _normaliseLegacyStatus(String status, {required bool signed}) {
  if (signed && status != 'issued' && status != 'revoked') {
    return 'signed';
  }

  switch (status) {
    case 'pending_consent':
    case 'consented':
      return 'pending_signature';
    case 'expired':
      // Old consent expiry must not permanently close a new no-consent report.
      return 'pending_signature';
    default:
      return status;
  }
}

String? _normaliseBlockedOn(
  String? blockedOn, {
  required String status,
  required bool signed,
}) {
  if (status == 'issued' || status == 'revoked' || status == 'declined') {
    return null;
  }

  if (signed || status == 'signed') return 'issue';

  if (blockedOn == null ||
      blockedOn == 'patient_consent' ||
      blockedOn == 'doctor_signature') {
    return 'doctor_signature';
  }

  return blockedOn;
}

String _statusLabel(dynamic serverLabel, String status) {
  final label = _str(serverLabel);

  // Do not surface obsolete consent wording even if an older backend sends it.
  if (label != null && !label.toLowerCase().contains('consent')) {
    return label;
  }

  switch (status) {
    case 'pending_signature':
      return 'Waiting for doctor signature';
    case 'signed':
      return 'Waiting for admin approval';
    case 'issued':
      return 'Shared with patient';
    case 'declined':
      return 'Declined by doctor';
    case 'revoked':
      return 'Withdrawn';
    default:
      return 'Draft';
  }
}

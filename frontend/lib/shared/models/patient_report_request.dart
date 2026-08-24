/// One tickable section in the patient-report builder.
///
/// Sensitivity is decided by the backend, never by the client — the UI just
/// reflects it, so a client-side edit can never widen a disclosure.
class ReportSectionOption {
  const ReportSectionOption({
    required this.key,
    required this.label,
    required this.description,
    required this.group,
    required this.requiresConsent,
    required this.clinical,
  });

  final String key;
  final String label;
  final String description;

  /// Personal / Account / Care / Clinical — how the tick-list is grouped.
  final String group;

  /// True when including this section forces the patient-consent step.
  final bool requiresConsent;

  /// True when including this section forces a doctor signature.
  final bool clinical;

  static ReportSectionOption fromJson(Map<String, dynamic> j) =>
      ReportSectionOption(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        description: '${j['description'] ?? ''}',
        group: '${j['group'] ?? 'Other'}',
        requiresConsent: j['requires_consent'] == true,
        clinical: j['clinical'] == true,
      );
}

/// Lifecycle of a customised patient report.
///
/// Nothing is disclosed until [status] reaches `issued`, which requires the
/// patient's consent (when restricted sections are ticked) and a doctor's
/// signature (when clinical sections are ticked).
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
    this.consentRequired = false,
    this.signatureRequired = false,
    this.blockedOn,
    this.consentSentAt,
    this.consentExpiresAt,
    this.consentExpired = false,
    this.consentAttempts = 0,
    this.consentedAt,
    this.consentMethod,
    this.declinedAt,
    this.declineReason,
    this.signedAt,
    this.signatureName,
    this.signatureNote,
    this.issuedAt,
    this.revokedAt,
    this.revokeReason,
    this.createdAt,
    this.awaitingMe = false,
    this.sectionDetails = const [],
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

  final bool consentRequired;
  final bool signatureRequired;

  /// draft / pending_consent / consented / declined / expired /
  /// pending_signature / signed / issued / revoked
  final String status;
  final String statusLabel;

  /// `patient_consent`, `doctor_signature`, `issue`, or null when closed.
  final String? blockedOn;

  final DateTime? consentSentAt;
  final DateTime? consentExpiresAt;
  final bool consentExpired;
  final int consentAttempts;
  final DateTime? consentedAt;
  final String? consentMethod;
  final DateTime? declinedAt;
  final String? declineReason;

  final DateTime? signedAt;
  final String? signatureName;
  final String? signatureNote;

  final DateTime? issuedAt;
  final DateTime? revokedAt;
  final String? revokeReason;
  final DateTime? createdAt;

  /// Set on the patient and doctor listings — this row needs *my* action.
  final bool awaitingMe;

  /// Patient-facing plain-language section descriptions.
  final List<Map<String, dynamic>> sectionDetails;

  bool get isIssued => status == 'issued';
  bool get isClosed =>
      status == 'issued' ||
      status == 'revoked' ||
      status == 'declined' ||
      status == 'expired';
  bool get awaitingConsent => blockedOn == 'patient_consent';
  bool get awaitingSignature => blockedOn == 'doctor_signature';
  bool get readyToIssue => blockedOn == 'issue';

  static PatientReportRequestItem fromJson(Map<String, dynamic> j) =>
      PatientReportRequestItem(
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
        consentRequired: j['consent_required'] == true,
        signatureRequired: j['signature_required'] == true,
        status: '${j['status'] ?? 'draft'}',
        statusLabel: '${j['status_label'] ?? ''}',
        blockedOn: _str(j['blocked_on']),
        consentSentAt: _date(j['consent_sent_at']),
        consentExpiresAt: _date(j['consent_expires_at']),
        consentExpired: j['consent_expired'] == true,
        consentAttempts: _int(j['consent_attempts']) ?? 0,
        consentedAt: _date(j['consented_at']),
        consentMethod: _str(j['consent_method']),
        declinedAt: _date(j['declined_at']),
        declineReason: _str(j['decline_reason']),
        signedAt: _date(j['signed_at']),
        signatureName: _str(j['signature_name']),
        signatureNote: _str(j['signature_note']),
        issuedAt: _date(j['issued_at']),
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
      );
}

/// The assembled report body — only ever produced from consented sections.
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
    this.consentGrantedAt,
    this.consentMethod,
    this.signedAt,
    this.signatureName,
    this.signatureNote,
  });

  final String title;
  final String? purpose;
  final String? recipient;
  final String? patientName;
  final String? patientUniqueId;
  final DateTime? generatedAt;
  final String? preparedBy;
  final DateTime? consentGrantedAt;
  final String? consentMethod;
  final DateTime? signedAt;
  final String? signatureName;
  final String? signatureNote;
  final List<ReportBlock> sections;

  static PatientReportDocument fromJson(Map<String, dynamic> j) {
    final consent = j['consent'] is Map
        ? (j['consent'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final signature = j['signature'] is Map
        ? (j['signature'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};

    return PatientReportDocument(
      title: '${j['title'] ?? 'Patient report'}',
      purpose: _str(j['purpose']),
      recipient: _str(j['recipient']),
      patientName: _str(j['patient_name']),
      patientUniqueId: _str(j['patient_unique_id']),
      generatedAt: _date(j['generated_at']),
      preparedBy: _str(j['prepared_by']),
      consentGrantedAt: _date(consent['granted_at']),
      consentMethod: _str(consent['method']),
      signedAt: _date(signature['signed_at']),
      signatureName: _str(signature['name']),
      signatureNote: _str(signature['note']),
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
              .map((e) => (
                    label: '${e['label'] ?? ''}',
                    value: '${e['value'] ?? ''}',
                  ))
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

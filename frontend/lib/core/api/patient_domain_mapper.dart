import '../../shared/models/appointment.dart';
import '../../shared/models/care_provider.dart';
import '../../shared/models/document.dart';
import '../../shared/models/medication.dart';
import '../../shared/models/message.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/support_ticket.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../../shared/models/vital_report_request.dart';
import 'patient_profile_mapper.dart';

/// Enum parsing + API JSON ↔ domain model mapping for clinical data.
class PatientDomainMapper {
  // ---------------------------------------------------------------------------
  // Enum parsers (API camelCase strings ↔ Flutter enums)
  // ---------------------------------------------------------------------------

  static RiskLevel riskFromApi(String? raw) {
    return RiskLevel.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => RiskLevel.unknown,
    );
  }

  static VitalKey vitalKeyFromApi(String raw) =>
      PatientProfileMapper.vitalKeyFromApi(raw);

  static DoseStatus doseStatusFromApi(String? raw) {
    return DoseStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => DoseStatus.pending,
    );
  }

  static MedicationSource medicationSourceFromApi(String? raw) {
    return MedicationSource.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => MedicationSource.doctorPrescribed,
    );
  }

  static AppointmentType appointmentTypeFromApi(String? raw) {
    return AppointmentType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AppointmentType.inPerson,
    );
  }

  static AppointmentStatus appointmentStatusFromApi(String? raw) {
    return AppointmentStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AppointmentStatus.scheduled,
    );
  }

  static DocumentCategory documentCategoryFromApi(String? raw) {
    return DocumentCategory.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => DocumentCategory.other,
    );
  }

  static DocumentFileType documentFileTypeFromApi(String? raw) {
    return DocumentFileType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => DocumentFileType.other,
    );
  }

  static NotificationKind notificationKindFromApi(String? raw) {
    return NotificationKind.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => NotificationKind.system,
    );
  }

  static TicketCategory ticketCategoryFromApi(String? raw) {
    return TicketCategory.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => TicketCategory.other,
    );
  }

  static TicketPriority ticketPriorityFromApi(String? raw) {
    return TicketPriority.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => TicketPriority.normal,
    );
  }

  static TicketStatus ticketStatusFromApi(String? raw) {
    return TicketStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => TicketStatus.open,
    );
  }

  static EmergencyKind emergencyKindFromApi(String? raw) {
    return EmergencyKind.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => EmergencyKind.other,
    );
  }

  static SosStatus sosStatusFromApi(String? raw) {
    return SosStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => SosStatus.active,
    );
  }

  static CareRequestStatus careRequestStatusFromApi(String? raw) {
    return CareRequestStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => CareRequestStatus.pending,
    );
  }

  static VitalReportStatus vitalReportStatusFromApi(String? raw) {
    return VitalReportStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => VitalReportStatus.pending,
    );
  }

  static UserRole userRoleFromApi(String? raw) {
    return UserRole.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => UserRole.doctor,
    );
  }

  static DateTime? parseDate(String? raw) =>
      raw == null || raw.isEmpty ? null : DateTime.parse(raw);

  static Object? notificationArgsFromApi(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      if (VitalKey.values.any((v) => v.name == raw)) {
        return vitalKeyFromApi(raw);
      }
      return raw;
    }
    if (raw is Map) {
      final vital = raw['vital'] as String?;
      if (vital != null) return vitalKeyFromApi(vital);
      return Map<String, dynamic>.from(raw);
    }
    return raw;
  }

  // ---------------------------------------------------------------------------
  // fromApi
  // ---------------------------------------------------------------------------

  static VitalReading vitalFromApi(Map<String, dynamic> json) {
    return VitalReading(
      id: json['id'] as String,
      vital: vitalKeyFromApi(json['vital'] as String),
      value: (json['value'] as num).toDouble(),
      secondaryValue: (json['secondary_value'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      risk: riskFromApi(json['risk'] as String?),
      note: json['note'] as String?,
    );
  }

  static Medication medicationFromApi(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as String,
      name: json['name'] as String,
      dosage: json['dosage'] as String,
      frequency: json['frequency'] as String,
      form: json['form'] as String? ?? 'Tablet',
      instructions: json['instructions'] as String?,
      prescribedBy: json['prescribed_by'] as String? ?? '',
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: parseDate(json['end_date'] as String?),
      active: json['active'] as bool? ?? true,
      refillsLeft: json['refills_left'] as int?,
      expiryDate: parseDate(json['expiry_date'] as String?),
      source: medicationSourceFromApi(json['source'] as String?),
    );
  }

  static MedicationDose doseFromApi(
    Map<String, dynamic> json, {
    required Map<String, Medication> medsById,
  }) {
    final medId = json['medication_id'] as String;
    final med = medsById[medId];
    return MedicationDose(
      id: json['id'] as String,
      medicationId: medId,
      name: med?.name ?? 'Medication',
      dosage: med?.dosage ?? '',
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      status: doseStatusFromApi(json['status'] as String?),
      takenAt: parseDate(json['taken_at'] as String?),
      instructions: med?.instructions,
    );
  }

  static Appointment appointmentFromApi(Map<String, dynamic> json) {
    return Appointment(
      id: json['id'] as String,
      doctorId: json['doctor_id'] as String? ?? '',
      doctorName: json['doctor_name'] as String,
      doctorSpecialty: json['doctor_specialty'] as String? ?? '',
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      type: appointmentTypeFromApi(json['type'] as String?),
      status: appointmentStatusFromApi(json['status'] as String?),
      reason: json['reason'] as String?,
      locationOrLink: json['location_or_link'] as String?,
      durationMinutes: json['duration_minutes'] as int? ?? 30,
      cancellationReason: json['cancellation_reason'] as String?,
    );
  }

  static MedicalDocument documentFromApi(Map<String, dynamic> json) {
    return MedicalDocument(
      id: json['id'] as String,
      title: json['title'] as String,
      category: documentCategoryFromApi(json['category'] as String?),
      fileType: documentFileTypeFromApi(json['file_type'] as String?),
      sizeBytes: json['size_bytes'] as int? ?? 0,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      uploadedBy: json['uploaded_by'] as String,
      description: json['description'] as String?,
      sharedWithDoctorId: json['shared_with_doctor_id'] as String?,
      hasFile: json['has_file'] as bool? ?? true,
    );
  }

  static ChatParticipant participantFromApi(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'] as String? ?? '',
      name: json['name'] as String,
      role: json['role'] as String? ?? 'doctor',
      specialty: json['specialty'] as String?,
    );
  }

  static ChatMessage messageFromApi(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    var senderId = json['sender_id'] as String? ?? 'me';
    if (currentUserId != null && senderId == currentUserId) {
      senderId = 'me';
    }
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: senderId,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
      read: json['read'] as bool? ?? false,
    );
  }

  static Conversation conversationFromApi(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final id = json['id'] as String;
    final participant = participantFromApi(
      json['participant'] as Map<String, dynamic>,
    );
    final lastRaw = json['last_message'] as Map<String, dynamic>?;
    final lastMessage = lastRaw != null
        ? messageFromApi(lastRaw, currentUserId: currentUserId)
        : ChatMessage(
            id: 'empty_$id',
            conversationId: id,
            senderId: 'me',
            body: '',
            sentAt: DateTime.now(),
            read: true,
          );
    return Conversation(
      id: id,
      participant: participant,
      lastMessage: lastMessage,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  static AppNotification notificationFromApi(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      kind: notificationKindFromApi(json['kind'] as String?),
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      read: json['read'] as bool? ?? false,
      resolved: json['resolved'] as bool? ?? false,
      resolvedAt: parseDate(json['resolved_at'] as String?),
      actionRoute: json['action_route'] as String?,
      actionArguments: notificationArgsFromApi(json['action_arguments']),
    );
  }

  static TicketReply ticketReplyFromApi(Map<String, dynamic> json) {
    return TicketReply(
      id: json['id'] as String,
      author: json['author'] as String,
      body: json['body'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
      isStaff: json['is_staff'] as bool? ?? false,
    );
  }

  static SupportTicket supportTicketFromApi(Map<String, dynamic> json) {
    final replies = (json['replies'] as List? ?? [])
        .map((e) => ticketReplyFromApi(e as Map<String, dynamic>))
        .toList();
    return SupportTicket(
      id: json['id'] as String,
      subject: json['subject'] as String,
      description: json['description'] as String,
      category: ticketCategoryFromApi(json['category'] as String?),
      priority: ticketPriorityFromApi(json['priority'] as String?),
      status: ticketStatusFromApi(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: parseDate(json['updated_at'] as String?),
      assignedTo: json['assigned_to'] as String?,
      assignedToName: json['assigned_to_name'] as String?,
      patientName: json['patient_name'] as String?,
      patientUserId: json['patient_user_id'] as String?,
      replies: replies,
    );
  }

  static SosEvent sosEventFromApi(Map<String, dynamic> json) {
    return SosEvent(
      id: json['id'] as String,
      kind: emergencyKindFromApi(json['kind'] as String?),
      triggeredAt: DateTime.parse(json['triggered_at'] as String),
      status: sosStatusFromApi(json['status'] as String?),
      locationLabel: json['location_label'] as String?,
      note: json['note'] as String?,
      respondedBy: json['responded_by'] as String?,
    );
  }

  static CareProvider careProviderFromApi(Map<String, dynamic> json) {
    return CareProvider(
      id: json['id'] as String,
      name: json['name'] as String,
      specialty: json['specialty'] as String,
      facility: json['facility'] as String,
      yearsExperience: json['years_experience'] as int? ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      totalReviews: json['total_reviews'] as int? ?? 0,
      bio: json['bio'] as String?,
      languages: List<String>.from(json['languages'] as List? ?? ['English']),
      assigned: json['assigned'] as bool? ?? false,
    );
  }

  static CareRequest careRequestFromApi(Map<String, dynamic> json) {
    return CareRequest(
      id: json['id'] as String,
      providerId: json['provider_id'] as String,
      providerName: json['provider_name'] as String,
      providerSpecialty: json['provider_specialty'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: careRequestStatusFromApi(json['status'] as String?),
      reason: json['reason'] as String?,
    );
  }

  static VitalReportRequest vitalReportRequestFromApi(
    Map<String, dynamic> json,
  ) {
    final vitals = (json['vitals'] as List? ?? [])
        .map((e) => vitalKeyFromApi(e as String))
        .toList();
    return VitalReportRequest(
      id: json['id'] as String,
      from: DateTime.parse(json['from'] as String),
      to: DateTime.parse(json['to'] as String),
      vitals: vitals,
      createdAt: DateTime.parse(json['created_at'] as String),
      status: vitalReportStatusFromApi(json['status'] as String?),
      currentResponder: userRoleFromApi(json['current_responder'] as String?),
      note: json['note'] as String?,
      respondedAt: parseDate(json['responded_at'] as String?),
      respondedBy: json['responded_by'] as String?,
      responseNote: json['response_note'] as String?,
      lastEscalatedAt: parseDate(json['last_escalated_at'] as String?),
    );
  }

  // ---------------------------------------------------------------------------
  // toApi (mutations)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> vitalToApi({
    required VitalKey vital,
    required double value,
    double? secondaryValue,
    DateTime? recordedAt,
    String? note,
  }) =>
      {
        'vital_key': vital.name,
        'value': value,
        if (secondaryValue != null) 'secondary_value': secondaryValue,
        if (recordedAt != null) 'recorded_at': recordedAt.toIso8601String(),
        if (note != null) 'note': note,
      };

  static Map<String, dynamic> medicationToApi(Medication med) => {
        'name': med.name,
        'dosage': med.dosage,
        'frequency': med.frequency,
        'form': med.form,
        'instructions': med.instructions,
        'prescribed_by': med.prescribedBy,
        'start_date': med.startDate.toIso8601String(),
        if (med.endDate != null) 'end_date': med.endDate!.toIso8601String(),
        if (med.expiryDate != null)
          'expiry_date': med.expiryDate!.toIso8601String(),
        if (med.refillsLeft != null) 'refills_left': med.refillsLeft,
        'source': med.source.name,
      };

  static Map<String, dynamic> doseStatusToApi(DoseStatus status) => {
        'status': status.name,
        if (status == DoseStatus.taken)
          'taken_at': DateTime.now().toIso8601String(),
      };

  static Map<String, dynamic> appointmentToApi(Appointment appt) => {
        'doctor_name': appt.doctorName,
        'doctor_specialty': appt.doctorSpecialty,
        'scheduled_at': appt.scheduledAt.toIso8601String(),
        'duration_minutes': appt.durationMinutes,
        'type': appt.type.name,
        if (appt.reason != null) 'reason': appt.reason,
        if (appt.locationOrLink != null)
          'location_or_link': appt.locationOrLink,
      };

  static Map<String, dynamic> documentMetaToApi({
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    String? description,
    String? sharedWithDoctorId,
  }) =>
      {
        'title': title,
        'category': category.name,
        'file_type': fileType.name,
        if (description != null) 'description': description,
        if (sharedWithDoctorId != null)
          'shared_with_doctor_id': sharedWithDoctorId,
      };

  static Map<String, dynamic> supportTicketToApi({
    required String subject,
    required String description,
    required TicketCategory category,
    TicketPriority priority = TicketPriority.normal,
  }) =>
      {
        'subject': subject,
        'description': description,
        'category': category.name,
        'priority': priority.name,
      };

  static Map<String, dynamic> sosTriggerToApi({
    required EmergencyKind kind,
    String? locationLabel,
    double? latitude,
    double? longitude,
    String? note,
  }) =>
      {
        'kind': kind.name,
        if (locationLabel != null) 'location_label': locationLabel,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (note != null) 'note': note,
      };

  static Map<String, dynamic> vitalReportRequestToApi({
    required DateTime from,
    required DateTime to,
    required List<VitalKey> vitals,
    String? note,
  }) =>
      {
        'range_from': from.toIso8601String(),
        'range_to': to.toIso8601String(),
        'vitals': vitals.map((v) => v.name).toList(),
        if (note != null) 'note': note,
      };
}

import '../../shared/models/announcement.dart';
import '../../shared/models/appointment.dart';
import '../../shared/models/care_provider.dart';
import '../../shared/models/document.dart';
import '../../shared/models/document_request.dart';
import '../../shared/models/meal_plan.dart';
import '../../shared/models/medication.dart';
import '../../shared/models/message.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/request_activity_event.dart';
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

  /// The API names notification kinds after what raised them, not after the
  /// client enum. Matching on enum name alone quietly filed every vital alert
  /// and every resolution notice under [NotificationKind.system], so a
  /// critical reading reached the patient's inbox as a grey info row.
  static NotificationKind notificationKindFromApi(String? raw) {
    return switch (raw) {
      'vital_warning' ||
      'vital_critical' ||
      'alert' => NotificationKind.vitalAlert,
      'alert_resolved' || 'sos_resolved' => NotificationKind.resolution,
      'care_request' => NotificationKind.careRequest,
      'new_user' => NotificationKind.profile,
      'medication_reminder' => NotificationKind.medication,
      'report_ready' => NotificationKind.report,
      _ => NotificationKind.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => NotificationKind.system,
      ),
    };
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

  /// The server writes `in_progress`; the enum is camelCase, so the two do
  /// not match by name and never will.
  static VitalReportStatus vitalReportStatusFromApi(String? raw) {
    if (raw == 'in_progress') return VitalReportStatus.inProgress;
    return VitalReportStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => VitalReportStatus.pending,
    );
  }

  static DocumentRequestStatus documentRequestStatusFromApi(String? raw) {
    if (raw == 'in_progress') return DocumentRequestStatus.inProgress;
    return DocumentRequestStatus.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => DocumentRequestStatus.pending,
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
      // The API names this `vital_key` on every alert it raises; reading only
      // `vital` meant a server-sent alert never linked back to the vital it
      // was about, so the patient's vital screen could not show which reading
      // the care team had acted on.
      final vital = (raw['vital'] ?? raw['vital_key']) as String?;
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
      source: switch (json['source'] as String?) {
        'clinician' => DocumentSource.clinician,
        'report' => DocumentSource.report,
        _ => DocumentSource.patient,
      },
      issuedReportId: json['issued_report_id'] as String?,
      removalRequested: json['removal_requested'] == true,
      removalRequestedAt: _optionalDate(json['removal_requested_at']),
      removalReason: json['removal_reason'] as String?,
      removalDeclinedAt: _optionalDate(json['removal_declined_at']),
      removalDeclinedReason: json['removal_declined_reason'] as String?,
      canRequestRemoval: json['can_request_removal'] == true,
    );
  }

  static DateTime? _optionalDate(Object? value) =>
      value is String ? DateTime.tryParse(value)?.toLocal() : null;

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
    final args = json['action_arguments'];
    final detail = args is Map ? args.cast<String, dynamic>() : null;

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
      actionArguments: notificationArgsFromApi(args),
      // `notificationArgsFromApi` collapses the payload to the vital it links
      // to, which is what navigation needs and all it needs. The outcome the
      // care team recorded lives in the same map and was being dropped with
      // it, so it is lifted out here into fields of its own.
      resolvedBy: detail?['resolved_by'] as String?,
      resolutionAction: resolutionActionLabel(
        detail?['resolution_action'] as String?,
        detail?['resolution_custom_action'] as String?,
      ),
      resolutionNote: detail?['resolution_note'] as String?,
      acknowledgedBy: detail?['acknowledged_by'] as String?,
    );
  }

  /// The responder's chosen action, in the words the patient reads. Mirrors
  /// `AlertResolutionNotifier::actionLabel` on the API side.
  static String? resolutionActionLabel(String? action, String? custom) {
    if (action == null || action.isEmpty) return null;
    if (action == 'other') {
      final trimmed = (custom ?? '').trim();
      return trimmed.isEmpty ? 'Other action' : trimmed;
    }
    return switch (action) {
      'patient_contacted' => 'Patient contacted',
      'medication_adjusted' => 'Medication adjusted',
      'follow_up_scheduled' => 'Follow-up scheduled',
      'monitored' => 'Monitored / observed',
      'referred' => 'Referred to care',
      'reading_error' => 'Reading error / false alarm',
      _ => 'Reviewed',
    };
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
      userId: json['user_id'] as String?,
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
      claimedById: json['claimed_by'] as String?,
      claimedByName: json['claimed_by_name'] as String?,
      claimedAt: parseDate(json['claimed_at'] as String?),
      waitingOn: json['waiting_on'] as String?,
      respondedAt: parseDate(json['responded_at'] as String?),
      respondedBy: json['responded_by'] as String?,
      responseNote: json['response_note'] as String?,
      resolvedAt: parseDate(json['resolved_at'] as String?),
      documentId: json['document_id'] as String?,
      lastEscalatedAt: parseDate(json['last_escalated_at'] as String?),
      events: RequestActivityEvent.listFromApi(json['events']),
    );
  }

  static DocumentRequest documentRequestFromApi(Map<String, dynamic> json) {
    return DocumentRequest(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Document request') as String,
      category: documentCategoryFromApi(json['category'] as String?),
      target: json['target'] == 'doctor'
          ? DocumentRequestTarget.doctor
          : DocumentRequestTarget.team,
      status: documentRequestStatusFromApi(json['status'] as String?),
      createdAt: parseDate(json['created_at'] as String?) ?? DateTime.now(),
      note: json['note'] as String?,
      targetDoctorId: json['target_doctor_id'] as String?,
      targetDoctorName: json['target_doctor_name'] as String?,
      neededBy: parseDate(json['needed_by'] as String?),
      overdue: json['overdue'] == true,
      claimedByName: json['claimed_by_name'] as String?,
      claimedAt: parseDate(json['claimed_at'] as String?),
      waitingOn: json['waiting_on'] as String?,
      resolvedAt: parseDate(json['resolved_at'] as String?),
      resolvedByName: json['resolved_by_name'] as String?,
      resolutionNote: json['resolution_note'] as String?,
      declineReason: json['decline_reason'] as String?,
      documentId: json['document_id'] as String?,
      events: RequestActivityEvent.listFromApi(json['events']),
    );
  }

  static Map<String, dynamic> documentRequestToApi({
    required String title,
    required DocumentCategory category,
    required DocumentRequestTarget target,
    String? note,
    String? targetDoctorId,
    DateTime? neededBy,
  }) => {
    'title': title,
    'category': category.name,
    'target': target.name,
    if (note != null && note.isNotEmpty) 'note': note,
    if (target == DocumentRequestTarget.doctor && targetDoctorId != null)
      'target_doctor_id': targetDoctorId,
    if (neededBy != null)
      'needed_by': neededBy.toIso8601String().split('T').first,
  };

  static MealType mealTypeFromApi(String? raw) => MealType.values.firstWhere(
    (t) => t.name == raw,
    orElse: () => MealType.general,
  );

  /// Clinician-assigned nutrition. Same payload the staff apps read, so the
  /// shared [StaffMealPlan] model is reused rather than duplicated.
  static StaffMealPlan mealPlanFromApi(Map<String, dynamic> json) =>
      StaffMealPlan(
        id: (json['id'] ?? '').toString(),
        patientId: (json['patient_id'] ?? '').toString(),
        patientName: (json['patient_name'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        mealType: mealTypeFromApi(json['meal_type'] as String?),
        description: json['description'] as String?,
        calories: (json['calories'] as num?)?.toInt(),
        protein: json['protein'] as String?,
        carbs: json['carbs'] as String?,
        fat: json['fat'] as String?,
        notes: json['notes'] as String?,
        assignedAt:
            parseDate(json['assigned_at'] as String?) ??
            parseDate(json['created_at'] as String?) ??
            DateTime.now(),
        assignedBy: (json['assigned_by'] as String?) ?? '',
        scheduledFor: parseDate(json['scheduled_for'] as String?),
        serveTime: json['serve_time'] as String?,
        conditionTag: json['condition_tag'] as String?,
        items: mealItemsFromApi(json['items']),
        source: MealPlanSource.fromApi(json['source'] as String?),
        adherence: MealAdherence.fromApi(json['adherence'] as String?),
        loggedAt: parseDate(json['logged_at'] as String?),
        patientNote: json['patient_note'] as String?,
      );

  /// `items` arrives as a JSON array of strings; older rows have null.
  static List<String> mealItemsFromApi(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  /// The write shape shared by `POST`/`PATCH /patient/meal-plans`. Only the
  /// fields a patient may set are sent; adherence moves through its own
  /// endpoint so a plan edit can never silently rewrite the progress log.
  static Map<String, dynamic> mealPlanToApi(StaffMealPlan plan) => {
        'title': plan.title,
        'meal_type': plan.mealType.name,
        if (plan.description != null) 'description': plan.description,
        if (plan.items.isNotEmpty) 'items': plan.items,
        if (plan.calories != null) 'calories': plan.calories,
        if (plan.protein != null) 'protein': plan.protein,
        if (plan.carbs != null) 'carbs': plan.carbs,
        if (plan.fat != null) 'fat': plan.fat,
        if (plan.notes != null) 'notes': plan.notes,
        if (plan.conditionTag != null) 'condition_tag': plan.conditionTag,
        'scheduled_for': _dayString(plan.planDate),
        if (plan.serveTime != null) 'serve_time': plan.serveTime,
      };

  static String _dayString(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static AppAnnouncement announcementFromApi(Map<String, dynamic> json) =>
      AppAnnouncement(
        id: (json['id'] ?? '').toString(),
        title: (json['title'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        audience: (json['audience'] as String?) ?? 'all',
        ctaLabel: json['cta_label'] as String?,
        ctaUrl: json['cta_url'] as String?,
        startsAt: parseDate(json['starts_at'] as String?),
        endsAt: parseDate(json['ends_at'] as String?),
        createdBy: json['created_by'] as String?,
        createdAt:
            parseDate(json['created_at'] as String?) ??
            parseDate(json['starts_at'] as String?) ??
            DateTime.now(),
      );

  // ---------------------------------------------------------------------------
  // toApi (mutations)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> vitalToApi({
    required VitalKey vital,
    required double value,
    double? secondaryValue,
    DateTime? recordedAt,
    String? note,
  }) => {
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
    if (appt.locationOrLink != null) 'location_or_link': appt.locationOrLink,
  };

  static Map<String, dynamic> documentMetaToApi({
    required String title,
    required DocumentCategory category,
    required DocumentFileType fileType,
    String? description,
    String? sharedWithDoctorId,
  }) => {
    'title': title,
    'category': category.name,
    'file_type': fileType.name,
    if (description != null) 'description': description,
    if (sharedWithDoctorId != null) 'shared_with_doctor_id': sharedWithDoctorId,
  };

  static Map<String, dynamic> supportTicketToApi({
    required String subject,
    required String description,
    required TicketCategory category,
    TicketPriority priority = TicketPriority.normal,
  }) => {
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
  }) => {
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
  }) => {
    'range_from': from.toIso8601String(),
    'range_to': to.toIso8601String(),
    'vitals': vitals.map((v) => v.name).toList(),
    if (note != null) 'note': note,
  };
}

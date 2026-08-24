import 'api_client.dart';

/// Thin wrapper around the `/doctor/*` endpoints. Each method returns the
/// raw decoded JSON `data` map (or `null`) so callers can choose to apply
/// optimistic updates and re-sync on success.
class DoctorApi {
  DoctorApi._();
  static final DoctorApi instance = DoctorApi._();

  // Alerts
  Future<void> acknowledgeAlert(String alertId) => _patch('alerts/$alertId/acknowledge');
  Future<void> resolveAlert(
    String alertId, {
    required String actionTaken,
    required String note,
    String? customAction,
  }) =>
      _patch('alerts/$alertId/resolve', body: {
        'action_taken': actionTaken,
        'note': note,
        if (customAction != null && customAction.isNotEmpty)
          'custom_action': customAction,
      });

  // Prescriptions
  Future<Map<String, dynamic>?> issuePrescription({
    required String patientUserId,
    required String name,
    required String dosage,
    required String frequency,
    required DateTime startDate,
    DateTime? endDate,
    String? instructions,
    int? refillsLeft,
  }) async {
    final res = await ApiClient.instance.post('/doctor/prescriptions', body: {
      'patient_user_id': int.parse(patientUserId),
      'name': name,
      'dosage': dosage,
      'frequency': frequency,
      'start_date': _date(startDate),
      if (endDate != null) 'end_date': _date(endDate),
      if (instructions != null) 'instructions': instructions,
      if (refillsLeft != null) 'refills_left': refillsLeft,
    });
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> revokePrescription(String medicationId) =>
      _patch('prescriptions/$medicationId/revoke');

  // Reports
  Future<Map<String, dynamic>?> saveReport({
    required String patientUserId,
    required String title,
    required String body,
    bool publish = false,
  }) async {
    final res = await ApiClient.instance.post('/doctor/reports', body: {
      'patient_user_id': int.parse(patientUserId),
      'title': title,
      'body': body,
      'publish': publish,
    });
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> updateReport(String reportId, {String? title, String? body}) =>
      _patch('reports/$reportId', body: {
        if (title != null) 'title': title,
        if (body != null) 'body': body,
      });

  Future<void> publishReport(String reportId) =>
      _patch('reports/$reportId/publish');

  Future<void> deleteReport(String reportId) =>
      ApiClient.instance.delete('/doctor/reports/$reportId');

  // Appointments
  Future<Map<String, dynamic>?> scheduleAppointment({
    required String patientUserId,
    required DateTime scheduledAt,
    int durationMinutes = 30,
    String type = 'inPerson',
    String? reason,
    String? locationOrLink,
  }) async {
    final res = await ApiClient.instance.post('/doctor/appointments', body: {
      'patient_user_id': int.parse(patientUserId),
      'scheduled_at': scheduledAt.toIso8601String(),
      'duration_minutes': durationMinutes,
      'type': type,
      if (reason != null) 'reason': reason,
      if (locationOrLink != null) 'location_or_link': locationOrLink,
    });
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> updateAppointment(
    String appointmentId, {
    String? status,
    DateTime? scheduledAt,
    String? cancellationReason,
  }) =>
      _patch('appointments/$appointmentId', body: {
        if (status != null) 'status': status,
        if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
        if (cancellationReason != null) 'cancellation_reason': cancellationReason,
      });

  // Vital report requests
  Future<void> fulfillVitalReportRequest(String requestId, {String? note}) =>
      _patch('vital-report-requests/$requestId/fulfill',
          body: {if (note != null) 'note': note});

  Future<void> escalateVitalReportRequest(String requestId) =>
      _patch('vital-report-requests/$requestId/escalate');

  // Care requests
  Future<void> acceptCareRequest(String requestId) =>
      _patch('care-requests/$requestId/accept');

  Future<void> declineCareRequest(String requestId, {String? reason}) =>
      _patch('care-requests/$requestId/decline',
          body: {if (reason != null) 'reason': reason});

  Future<void> resolveSos(String eventId, {required String status}) =>
      _patch('sos/$eventId', body: {'status': status});

  // Messages
  Future<List<Map<String, dynamic>>> listConversations() async {
    final res = await ApiClient.instance.get('/doctor/conversations');
    final list = res['data']?['conversations'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<List<Map<String, dynamic>>> loadThread(String conversationId) async {
    final res = await ApiClient.instance
        .get('/doctor/conversations/$conversationId/messages');
    final list = res['data']?['messages'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<Map<String, dynamic>?> sendMessage(
    String conversationId,
    String body,
  ) async {
    final res = await ApiClient.instance.post(
      '/doctor/conversations/$conversationId/messages',
      body: {'body': body},
    );
    return (res['data']?['message'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> markConversationRead(String conversationId) async {
    await ApiClient.instance.post('/doctor/conversations/$conversationId/read');
  }

  // Meal plans
  Future<Map<String, dynamic>?> assignMealPlan({
    required String patientUserId,
    required String title,
    required String mealType,
    String? description,
    int? calories,
    String? protein,
    String? carbs,
    String? fat,
    String? notes,
  }) async {
    final res = await ApiClient.instance.post('/doctor/meal-plans', body: {
      'patient_user_id': int.parse(patientUserId),
      'title': title,
      'meal_type': mealType,
      if (description != null) 'description': description,
      if (calories != null) 'calories': calories,
      if (protein != null) 'protein': protein,
      if (carbs != null) 'carbs': carbs,
      if (fat != null) 'fat': fat,
      if (notes != null) 'notes': notes,
    });
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> removeMealPlan(String mealPlanId) =>
      ApiClient.instance.delete('/doctor/meal-plans/$mealPlanId');

  // Patient detail pull
  Future<Map<String, dynamic>?> patientDetail(String patientUserId) async {
    final res = await ApiClient.instance.get('/doctor/patients/$patientUserId');
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  /// Clinician chart edit — partial update of the patient's health profile.
  /// Returns the list of changed-field labels the server applied.
  Future<List<String>> updatePatientChart({
    required String patientUserId,
    required Map<String, dynamic> healthDelta,
    String? note,
  }) async {
    final res = await ApiClient.instance.patch(
      '/doctor/patients/$patientUserId/chart',
      body: {
        ...healthDelta,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    final changes = (data?['changes'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
    return changes;
  }

  /// Assign vital types the patient must track.
  Future<List<String>> updateAssignedVitals({
    required String patientUserId,
    required List<String> vitalKeys,
    String? note,
  }) async {
    final res = await ApiClient.instance.patch(
      '/doctor/patients/$patientUserId/assigned-vitals',
      body: {
        'assigned_vitals': vitalKeys,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    return (data?['assigned_vitals'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  // Vital catalog
  Future<Map<String, dynamic>?> createVitalCatalogEntry(
    Map<String, dynamic> body,
  ) async {
    final res =
        await ApiClient.instance.post('/doctor/vital-catalog', body: body);
    return (res['data']?['entry'] as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> updateVitalCatalogEntry(
    String id,
    Map<String, dynamic> body,
  ) async {
    final res = await ApiClient.instance.patch(
      '/doctor/vital-catalog/$id',
      body: body,
    );
    return (res['data']?['entry'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> deleteVitalCatalogEntry(String id) async {
    await ApiClient.instance.delete('/doctor/vital-catalog/$id');
  }

  // Patient reports awaiting this doctor's signature.
  Future<List<Map<String, dynamic>>> listReportRequests() async {
    final res = await ApiClient.instance.get('/doctor/report-requests');
    final list = res['data']?['report_requests'] as List? ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// Full preview of what will be disclosed — a signature is given against
  /// real content, not a list of section names.
  Future<Map<String, dynamic>?> previewReportRequest(String id) async {
    final res = await ApiClient.instance.get('/doctor/report-requests/$id');
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> signReportRequest(
    String id, {
    required String signatureName,
    String? note,
  }) async {
    final res = await ApiClient.instance.post(
      '/doctor/report-requests/$id/sign',
      body: {
        'signature_name': signatureName,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return (res['data']?['report_request'] as Map?)?.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> declineReportRequest(
    String id, {
    required String reason,
  }) async {
    final res = await ApiClient.instance.post(
      '/doctor/report-requests/$id/decline',
      body: {'reason': reason},
    );
    return (res['data']?['report_request'] as Map?)?.cast<String, dynamic>();
  }

  // ---------------------------------------------------------------------------
  Future<void> _patch(String path, {Map<String, dynamic>? body}) async {
    await ApiClient.instance.patch('/doctor/$path', body: body);
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

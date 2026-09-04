import 'dart:typed_data';

import '../env/app_env.dart';
import 'api_client.dart';

/// Thin wrapper around the `/doctor/*` endpoints. Each method returns the
/// raw decoded JSON `data` map (or `null`) so callers can choose to apply
/// optimistic updates and re-sync on success.
class DoctorApi {
  DoctorApi._();
  static final DoctorApi instance = DoctorApi._();

  // Alerts
  Future<void> acknowledgeAlert(String alertId) =>
      _patch('alerts/$alertId/acknowledge');
  Future<void> resolveAlert(
    String alertId, {
    required String actionTaken,
    required String note,
    String? customAction,
  }) => _patch(
    'alerts/$alertId/resolve',
    body: {
      'action_taken': actionTaken,
      'note': note,
      if (customAction != null && customAction.isNotEmpty)
        'custom_action': customAction,
    },
  );

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
    final res = await ApiClient.instance.post(
      '/doctor/prescriptions',
      body: {
        'patient_user_id': int.parse(patientUserId),
        'name': name,
        'dosage': dosage,
        'frequency': frequency,
        'start_date': _date(startDate),
        if (endDate != null) 'end_date': _date(endDate),
        if (instructions != null) 'instructions': instructions,
        if (refillsLeft != null) 'refills_left': refillsLeft,
      },
    );
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
    final res = await ApiClient.instance.post(
      '/doctor/reports',
      body: {
        'patient_user_id': int.parse(patientUserId),
        'title': title,
        'body': body,
        'publish': publish,
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> updateReport(String reportId, {String? title, String? body}) =>
      _patch(
        'reports/$reportId',
        body: {
          if (title != null) 'title': title,
          if (body != null) 'body': body,
        },
      );

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
    final res = await ApiClient.instance.post(
      '/doctor/appointments',
      body: {
        'patient_user_id': int.parse(patientUserId),
        'scheduled_at': scheduledAt.toIso8601String(),
        'duration_minutes': durationMinutes,
        'type': type,
        if (reason != null) 'reason': reason,
        if (locationOrLink != null) 'location_or_link': locationOrLink,
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  Future<void> updateAppointment(
    String appointmentId, {
    String? status,
    DateTime? scheduledAt,
    String? cancellationReason,
  }) => _patch(
    'appointments/$appointmentId',
    body: {
      if (status != null) 'status': status,
      if (scheduledAt != null) 'scheduled_at': scheduledAt.toIso8601String(),
      if (cancellationReason != null) 'cancellation_reason': cancellationReason,
    },
  );

  // ---------------------------------------------------------------------------
  // Vital report requests — a shared queue with a single owner.
  //
  // Claiming is a real request rather than a local flag because it is the
  // thing that stops two clinicians writing the same report: the server
  // decides who won, and a loser gets a 409 carrying the winner's name.
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> claimVitalReportRequest(String requestId) =>
      _patchData('vital-report-requests/$requestId/claim');

  Future<Map<String, dynamic>?> releaseVitalReportRequest(
    String requestId, {
    String? note,
  }) => _patchData(
    'vital-report-requests/$requestId/release',
    body: {if (note != null && note.isNotEmpty) 'note': note},
  );

  Future<Map<String, dynamic>?> fulfillVitalReportRequest(
    String requestId, {
    String? note,
  }) => _patchData(
    'vital-report-requests/$requestId/fulfill',
    body: {if (note != null) 'note': note},
  );

  Future<Map<String, dynamic>?> escalateVitalReportRequest(
    String requestId, {
    String? note,
  }) => _patchData(
    'vital-report-requests/$requestId/escalate',
    body: {if (note != null && note.isNotEmpty) 'note': note},
  );

  // ---------------------------------------------------------------------------
  // Document requests — the patient asking the team for a document.
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> documentRequests() async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get('/doctor/document-requests');
    return ((res['data']?['requests'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> claimDocumentRequest(String requestId) =>
      _patchData('document-requests/$requestId/claim');

  Future<Map<String, dynamic>?> releaseDocumentRequest(
    String requestId, {
    String? note,
  }) => _patchData(
    'document-requests/$requestId/release',
    body: {if (note != null && note.isNotEmpty) 'note': note},
  );

  Future<Map<String, dynamic>?> declineDocumentRequest(
    String requestId, {
    required String reason,
  }) => _patchData(
    'document-requests/$requestId/decline',
    body: {'reason': reason},
  );

  // Care-request triage is an admin / mCare-assistant responsibility — a
  // doctor sees the care team they were assigned to, never the accept or
  // decline decision. The endpoints these called no longer exist.

  Future<void> resolveSos(
    String eventId, {
    required String status,
    String? resolution,
    String? resolutionNote,
  }) => _patch(
    'sos/$eventId',
    body: {
      'status': status,
      if (resolution != null) 'resolution': resolution,
      if (resolutionNote != null && resolutionNote.trim().isNotEmpty)
        'resolution_note': resolutionNote.trim(),
    },
  );

  // Messages
  Future<List<Map<String, dynamic>>> listConversations() async {
    final res = await ApiClient.instance.get('/doctor/conversations');
    final list = res['data']?['conversations'] as List? ?? [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<List<Map<String, dynamic>>> loadThread(String conversationId) async {
    final res = await ApiClient.instance.get(
      '/doctor/conversations/$conversationId/messages',
    );
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
  //
  // One call covers several patients and several days: pass [patientUserIds]
  // and/or [scheduledFor] with more than one entry and the API writes the plan
  // once per patient per day. A single assign is the same call with one of
  // each, so callers that only ever assign one plan need no special case.
  Future<Map<String, dynamic>?> assignMealPlan({
    required String patientUserId,
    required String title,
    required String mealType,
    List<String>? patientUserIds,
    List<DateTime>? scheduledFor,
    String? serveTime,
    String? conditionTag,
    List<String>? items,
    String? description,
    int? calories,
    String? protein,
    String? carbs,
    String? fat,
    String? notes,
  }) async {
    final res = await ApiClient.instance.post(
      '/doctor/meal-plans',
      body: {
        if (patientUserIds == null || patientUserIds.isEmpty)
          'patient_user_id': int.parse(patientUserId)
        else
          'patient_user_ids': patientUserIds.map(int.parse).toList(),
        'title': title,
        'meal_type': mealType,
        if (scheduledFor != null && scheduledFor.isNotEmpty)
          'scheduled_for': scheduledFor.map(_dayString).toList(),
        if (serveTime != null) 'serve_time': serveTime,
        if (conditionTag != null) 'condition_tag': conditionTag,
        if (items != null && items.isNotEmpty) 'items': items,
        if (description != null) 'description': description,
        if (calories != null) 'calories': calories,
        if (protein != null) 'protein': protein,
        if (carbs != null) 'carbs': carbs,
        if (fat != null) 'fat': fat,
        if (notes != null) 'notes': notes,
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  static String _dayString(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

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
      body: {...healthDelta, if (note != null && note.isNotEmpty) 'note': note},
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
    final res = await ApiClient.instance.post(
      '/doctor/vital-catalog',
      body: body,
    );
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

  // Patient reports awaiting this doctor's review/signature.
  // Patient consent is not part of the report-request flow. The doctor
  // reviews the generated content and either signs or declines it.
  Future<List<Map<String, dynamic>>> listReportRequests() async {
    final res = await ApiClient.instance.get('/doctor/report-requests');
    final list = res['data']?['report_requests'] as List? ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  /// Full preview of what will be disclosed — a signature is given against
  /// real content, not a list of section names.
  /// The report as a page the doctor can open at full width and print.
  ///
  /// `previewReportRequest` renders it inside a sheet, which is fine for a
  /// glance and poor for what a signature actually requires — reading a long
  /// document properly. Fetched through the authenticated client rather than
  /// opened as a link: the route is bearer-authenticated, so a bare URL would
  /// arrive without the token and 401.
  Future<Uint8List> reportRequestDocumentBytes(String id) {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('API disabled.');
    }

    return ApiClient.instance.getBytes('/doctor/report-requests/$id/document');
  }

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

  /// [_patch] for the calls whose answer matters — a claim has to come back
  /// with the row the server actually holds, not just "no exception thrown".
  Future<Map<String, dynamic>?> _patchData(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch('/doctor/$path', body: body);
    return (res['data']?['request'] as Map?)?.cast<String, dynamic>();
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../env/app_env.dart';
import 'api_client.dart';
import 'multipart_file_builder.dart';

typedef JsonMap = Map<String, dynamic>;

/// Thin facade over the `/admin/*` endpoints. Every method returns raw
/// JSON maps — UI state stores convert them via `staff_mapper.dart`.
class AdminApi {
  AdminApi._();
  static final AdminApi instance = AdminApi._();

  // ---------------- SOS ----------------
  Future<List<JsonMap>> listSosEvents({String status = 'active'}) async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/sos-events?status=$status');
    return _list(res, 'sos_events');
  }

  Future<void> resolveSos(String eventId, {required String status}) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch(
      '/admin/sos-events/$eventId',
      body: {'status': status},
    );
  }

  // ---------------- Approvals ----------------
  Future<List<JsonMap>> listApprovals({String status = 'pending'}) async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/approvals?status=$status');
    return _list(res, 'applications');
  }

  Future<JsonMap?> approveApplication(String id, {String? note}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/approvals/$id/approve',
      body: note == null ? {} : {'note': note},
    );
    return _obj(res, 'user');
  }

  Future<JsonMap?> rejectApplication(String id, {required String reason}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/approvals/$id/reject',
      body: {'reason': reason},
    );
    return _obj(res, 'user');
  }

  Future<JsonMap?> requestApplicationInfo(String id, {required String message}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/admin/approvals/$id/request-info',
      body: {'message': message},
    );
    return _obj(res, 'user');
  }

  // ---------------- Care requests ----------------
  Future<List<JsonMap>> listCareRequests({String? status}) async {
    if (!AppEnv.backendEnabled) return [];
    final q = status != null ? '?status=$status' : '';
    final res = await ApiClient.instance.get('/admin/care-requests$q');
    return _list(res, 'care_requests');
  }

  Future<JsonMap?> routeCareRequest(String id, {String? providerId}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/care-requests/$id/route',
      body: providerId == null ? {} : {'provider_id': providerId},
    );
    return _obj(res, 'care_request');
  }

  Future<JsonMap?> cancelCareRequest(String id, {required String reason}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/care-requests/$id/cancel',
      body: {'reason': reason},
    );
    return _obj(res, 'care_request');
  }

  // ---------------- Assignments ----------------
  Future<List<JsonMap>> listAssignments({String? patientId, String? providerId}) async {
    if (!AppEnv.backendEnabled) return [];
    final params = <String, String>{};
    if (patientId != null) params['patient_id'] = patientId;
    if (providerId != null) params['provider_id'] = providerId;
    final q = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final res = await ApiClient.instance.get('/admin/assignments$q');
    return _list(res, 'assignments');
  }

  Future<JsonMap?> createAssignment({
    required String patientUserId,
    required String providerId,
    String? role,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/admin/assignments',
      body: {
        'patient_user_id': patientUserId,
        'provider_id': providerId,
        if (role != null) 'role': role,
      },
    );
    return _obj(res, 'assignment');
  }

  Future<void> removeAssignment(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.delete('/admin/assignments/$id');
  }

  // ---------------- Users ----------------
  Future<JsonMap> listUsers({
    String? role,
    String? status,
    String? query,
    int page = 1,
    int perPage = 25,
  }) async {
    if (!AppEnv.backendEnabled) return {'users': <JsonMap>[], 'meta': {}};
    final params = <String, String>{'page': '$page', 'per_page': '$perPage'};
    if (role != null) params['role'] = role;
    if (status != null) params['status'] = status;
    if (query != null && query.isNotEmpty) params['query'] = query;
    final q = '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final res = await ApiClient.instance.get('/admin/users$q');
    return res['data'] as JsonMap? ?? {};
  }

  Future<JsonMap?> createUser({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    required String role,
    String? specialty,
    String? licenseNumber,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/admin/users',
      body: {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        if (phone != null) 'phone': phone,
        'role': role,
        if (specialty != null && specialty.isNotEmpty) 'specialty': specialty,
        if (licenseNumber != null && licenseNumber.isNotEmpty)
          'license_number': licenseNumber,
      },
    );
    return res['data'] as JsonMap?;
  }

  Future<JsonMap?> changeUserRole(String id, {required String role, required String reason}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/users/$id/role',
      body: {'role': role, 'reason': reason},
    );
    return _obj(res, 'user');
  }

  Future<JsonMap?> changeUserStatus(String id, {required String status}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/users/$id/status',
      body: {'status': status},
    );
    return _obj(res, 'user');
  }

  Future<String?> resetUserPassword(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post('/admin/users/$id/password-reset');
    return res['data']?['temp_password'] as String?;
  }

  /// Clear login lockout / failed-attempt counter after assisting a user.
  Future<JsonMap?> unlockUser(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post('/admin/users/$id/unlock');
    return _obj(res, 'user');
  }

  /// Reissue a 7-day invite token for staff who have not completed setup.
  Future<JsonMap?> resendUserInvite(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post('/admin/users/$id/resend-invite');
    return res['data'] as JsonMap?;
  }

  Future<JsonMap?> uploadApprovalCredential(
    String userId, {
    required PlatformFile file,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final multipart = await MultipartFileBuilder.fromPlatformFile(file);
    final res = await ApiClient.instance.postMultipart(
      '/admin/approvals/$userId/credential',
      fields: const {},
      files: [multipart],
    );
    return res['data']?['application'] as JsonMap?;
  }

  Future<Uint8List> fetchApprovalCredentialBytes(String userId) {
    return ApiClient.instance.getBytes(
      '/admin/approvals/$userId/credential/stream',
    );
  }

  /// Download audit CSV export bytes.
  Future<Uint8List?> exportAudit({String? from, String? to}) async {
    if (!AppEnv.backendEnabled) return null;
    final params = <String, String>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    final q = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    return ApiClient.instance.getBytes('/admin/audit/export$q');
  }

  /// Read-only clinical profile for a patient account.
  Future<JsonMap?> patientProfile(String patientUserId) async {
    if (!AppEnv.backendEnabled) return null;
    final res =
        await ApiClient.instance.get('/admin/patients/$patientUserId');
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  // ---------------- Permissions (admin-only) ----------------
  Future<JsonMap> listAllPermissions() async {
    if (!AppEnv.backendEnabled) return {'grants': <JsonMap>[], 'available_keys': <String>[]};
    final res = await ApiClient.instance.get('/admin/permissions');
    return res['data'] as JsonMap? ?? {};
  }

  Future<List<String>> getUserPermissions(String userId) async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/permissions/$userId');
    final list = res['data']?['permissions'] as List? ?? const [];
    return list.map((e) => e.toString()).toList();
  }

  Future<List<String>> syncUserPermissions(String userId, List<String> keys) async {
    if (!AppEnv.backendEnabled) return keys;
    final res = await ApiClient.instance.patch(
      '/admin/permissions/$userId',
      body: {'permissions': keys},
    );
    final list = res['data']?['permissions'] as List? ?? const [];
    return list.map((e) => e.toString()).toList();
  }

  // ---------------- Announcements ----------------
  Future<List<JsonMap>> listAnnouncements({String? audience, bool? published}) async {
    if (!AppEnv.backendEnabled) return [];
    final params = <String, String>{};
    if (audience != null) params['audience'] = audience;
    if (published != null) params['published'] = published ? '1' : '0';
    final q = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final res = await ApiClient.instance.get('/admin/announcements$q');
    return _list(res, 'announcements');
  }

  Future<JsonMap?> createAnnouncement(JsonMap payload) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post('/admin/announcements', body: payload);
    return _obj(res, 'announcement');
  }

  Future<JsonMap?> updateAnnouncement(String id, JsonMap payload) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch('/admin/announcements/$id', body: payload);
    return _obj(res, 'announcement');
  }

  Future<JsonMap?> publishAnnouncement(String id, {required bool publish}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/announcements/$id/publish',
      body: {'publish': publish},
    );
    return _obj(res, 'announcement');
  }

  Future<void> deleteAnnouncement(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.delete('/admin/announcements/$id');
  }

  // ---------------- Audit ----------------
  Future<JsonMap> listAudit({
    String? actor,
    String? action,
    String? category,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int perPage = 50,
  }) async {
    if (!AppEnv.backendEnabled) return {'audit': <JsonMap>[], 'meta': {}};
    final params = <String, String>{'page': '$page', 'per_page': '$perPage'};
    if (actor != null) params['actor'] = actor;
    if (action != null) params['action'] = action;
    if (category != null) params['category'] = category;
    if (from != null) params['from'] = from.toIso8601String();
    if (to != null) params['to'] = to.toIso8601String();
    final q = '?${params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final res = await ApiClient.instance.get('/admin/audit$q');
    return res['data'] as JsonMap? ?? {};
  }

  // ---------------- Security incidents ----------------
  Future<List<JsonMap>> listSecurityIncidents({bool? resolved}) async {
    if (!AppEnv.backendEnabled) return [];
    final q = resolved == null ? '' : '?resolved=${resolved ? '1' : '0'}';
    final res = await ApiClient.instance.get('/admin/security-incidents$q');
    return _list(res, 'incidents');
  }

  Future<void> acknowledgeSecurityIncident(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch('/admin/security-incidents/$id');
  }

  // ---------------- Support tickets ----------------
  Future<List<JsonMap>> listSupportTickets({String? status}) async {
    if (!AppEnv.backendEnabled) return [];
    final q = status != null ? '?status=$status' : '';
    final res = await ApiClient.instance.get('/admin/support-tickets$q');
    return _list(res, 'tickets');
  }

  Future<JsonMap?> replyToTicket(String id, {required String body}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/admin/support-tickets/$id/replies',
      body: {'body': body},
    );
    return _obj(res, 'ticket');
  }

  Future<JsonMap?> resolveTicket(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res =
        await ApiClient.instance.patch('/admin/support-tickets/$id/resolve');
    return _obj(res, 'ticket');
  }

  Future<JsonMap?> closeTicket(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch('/admin/support-tickets/$id/close');
    return _obj(res, 'ticket');
  }

  Future<JsonMap?> reopenTicket(String id) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch('/admin/support-tickets/$id/reopen');
    return _obj(res, 'ticket');
  }

  Future<JsonMap?> assignTicket(String id, {String? assigneeId}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/admin/support-tickets/$id/assign',
      body: {'assignee_id': assigneeId},
    );
    return _obj(res, 'ticket');
  }

  // ---------------- Conversations ----------------
  Future<List<JsonMap>> listConversations() async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/conversations');
    return _list(res, 'conversations');
  }

  Future<List<JsonMap>> threadMessages(String id) async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/conversations/$id/messages');
    return _list(res, 'messages');
  }

  Future<JsonMap?> sendMessage(String id, {required String body}) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/admin/conversations/$id/messages',
      body: {'body': body},
    );
    return _obj(res, 'message');
  }

  Future<void> markConversationRead(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post('/admin/conversations/$id/read');
  }

  Future<JsonMap?> createConversation(String userId) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/admin/conversations',
      body: {'user_id': userId},
    );
    return _obj(res, 'conversation');
  }

  // ---------------- Notifications ----------------
  Future<List<JsonMap>> listNotifications() async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/notifications');
    return _list(res, 'notifications');
  }

  Future<void> markNotificationRead(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch('/admin/notifications/$id/read');
  }

  Future<void> resolveNotification(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch('/admin/notifications/$id/resolve');
  }

  Future<void> markAllNotificationsRead() async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.post('/admin/notifications/read-all');
  }

  // ---------------- System settings ----------------
  Future<List<JsonMap>> listSystemSettings() async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/system/settings');
    return _list(res, 'settings');
  }

  Future<void> updateSystemSetting(String key, {required bool value}) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch(
      '/admin/system/settings/$key',
      body: {'value': value},
    );
  }

  // ---------------- Vital catalog (admin read) ----------------
  Future<List<JsonMap>> listVitalCatalog() async {
    if (!AppEnv.backendEnabled) return [];
    final res = await ApiClient.instance.get('/admin/vital-catalog');
    return _list(res, 'vital_catalog');
  }

  Future<JsonMap?> createVitalCatalogEntry(JsonMap body) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post('/admin/vital-catalog', body: body);
    return _obj(res, 'entry');
  }

  Future<JsonMap?> updateVitalCatalogEntry(String id, JsonMap body) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch('/admin/vital-catalog/$id', body: body);
    return _obj(res, 'entry');
  }

  Future<void> deleteVitalCatalogEntry(String id) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.delete('/admin/vital-catalog/$id');
  }

  // ---------------- Admin session (single payload) ----------------
  Future<JsonMap?> fetchSession() async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.get('/admin/session');
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  // ---------------- System-wide alerts ----------------
  Future<List<JsonMap>> listAlerts({bool openOnly = false}) async {
    if (!AppEnv.backendEnabled) return [];
    final q = openOnly ? '?open_only=1' : '';
    final res = await ApiClient.instance.get('/admin/alerts$q');
    return _list(res, 'alerts');
  }

  Future<void> acknowledgeAlert(String alertId) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch('/admin/alerts/$alertId/acknowledge');
  }

  Future<void> resolveAlert(
    String alertId, {
    required String actionTaken,
    required String note,
    String? customAction,
  }) async {
    if (!AppEnv.backendEnabled) return;
    await ApiClient.instance.patch(
      '/admin/alerts/$alertId/resolve',
      body: {
        'action_taken': actionTaken,
        'note': note,
        if (customAction != null) 'custom_action': customAction,
      },
    );
  }

  // ---------------- Analytics ----------------
  Future<JsonMap> fetchKpis() async {
    if (!AppEnv.backendEnabled) return {};
    final res = await ApiClient.instance.get('/admin/analytics/kpis');
    return (res['data']?['kpis'] as JsonMap?) ?? {};
  }

  Future<List<JsonMap>> fetchTimeseries({
    required String metric,
    DateTime? from,
    DateTime? to,
  }) async {
    if (!AppEnv.backendEnabled) return [];
    final params = <String, String>{'metric': metric};
    if (from != null) params['from'] = from.toIso8601String().substring(0, 10);
    if (to != null) params['to'] = to.toIso8601String().substring(0, 10);
    final q = '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    final res = await ApiClient.instance.get('/admin/analytics/timeseries$q');
    final list = res['data']?['series'] as List? ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  // ---------------- helpers ----------------
  List<JsonMap> _list(JsonMap res, String key) {
    final list = res['data']?[key] as List? ?? const [];
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  JsonMap? _obj(JsonMap res, String key) {
    final obj = res['data']?[key];
    if (obj is Map) return obj.cast<String, dynamic>();
    return null;
  }
}

import '../../core/api/admin_api.dart';
import '../../core/api/patient_domain_mapper.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../models/message.dart';
import '../models/user_role.dart';
import '../state/messages_state.dart';
import '../state/notification_state.dart';
import '../state/staff_state.dart';
import '../state/support_state.dart';
import 'admin_sos_service.dart';

/// Pulls admin / assistant session data from `/admin/*` endpoints and
/// rehydrates `StaffState`. Permission-gated calls fail silently so
/// assistants only hydrate what they are allowed to see.
class AdminSessionService {
  AdminSessionService._();
  static final AdminSessionService instance = AdminSessionService._();

  Future<bool> syncFromApi({bool background = false}) async {
    if (!AppEnv.backendEnabled) {
      StaffState.instance.seedDemo();
      return true;
    }

    try {
      StaffState.instance.clearAdminBuckets();
      await _pullFromApi();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pullFromApi() async {
    final session = await AdminApi.instance.fetchSession();
    if (session != null) {
      _applySessionPayload(session);
      await _syncMessages();
      StaffState.instance.notifyIfSessionChanged();
      return;
    }

    await Future.wait([
      _syncUsers(),
      _syncApprovals(),
      _syncCareRequests(),
      _syncAssignments(),
      _syncAudit(),
      _syncSystemSettings(),
      _syncVitalCatalog(),
      _syncSupportTickets(),
      _syncAlerts(),
      _syncNotifications(),
      AdminSosService.instance.syncFromApi(),
      _syncMessages(),
    ]);
    StaffState.instance.notifyIfSessionChanged();
  }

  Future<void> _try(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // Permission denied or endpoint unavailable — skip bucket.
    }
  }

  Future<void> _syncUsers() => _try(() async {
        final data = await AdminApi.instance.listUsers(perPage: 100);
        final rawList = data['users'] as List? ?? const [];
        final users = rawList
            .map((e) => StaffMapper.directoryUserFromApiFull(
                  (e as Map).cast<String, dynamic>(),
                ))
            .toList();
        StaffState.instance.mergeUsers(users);
      });

  Future<void> _syncApprovals() => _try(() async {
        final rows = await AdminApi.instance.listApprovals();
        final approvals =
            rows.map((e) => StaffMapper.approvalFromApi(e)).toList();
        StaffState.instance.mergeApprovals(approvals);
      });

  Future<void> _syncCareRequests() => _try(() async {
        final rows = await AdminApi.instance.listCareRequests();
        final items =
            rows.map((e) => StaffMapper.careRequestFromApi(e)).toList();
        StaffState.instance.mergeCareRequests(items);
      });

  Future<void> _syncAssignments() => _try(() async {
        final rows = await AdminApi.instance.listAssignments();
        final items =
            rows.map((e) => StaffMapper.assignmentFromApi(e)).toList();
        StaffState.instance.mergeAssignments(items);
      });

  Future<void> _syncAudit() => _try(() async {
        final data = await AdminApi.instance.listAudit(perPage: 50);
        final rawList = data['audit'] as List? ?? const [];
        final entries = rawList
            .map((e) => StaffMapper.auditFromApi(
                  (e as Map).cast<String, dynamic>(),
                ))
            .toList();
        StaffState.instance.mergeAudit(entries);
      });

  Future<void> _syncSystemSettings() => _try(() async {
        final rows = await AdminApi.instance.listSystemSettings();
        final settings =
            rows.map((e) => StaffMapper.systemSettingFromApi(e)).toList();
        if (settings.isNotEmpty) {
          StaffState.instance.mergeSystemSettings(settings);
        }
      });

  Future<void> _syncVitalCatalog() => _try(() async {
        final role = AuthState.instance.user?.role;
        if (role == UserRole.mcareAssistant &&
            !AuthState.instance
                .hasAssistantPermission('can_manage_vital_catalog')) {
          return;
        }
        final rows = await AdminApi.instance.listVitalCatalog();
        final entries =
            rows.map((e) => StaffMapper.vitalCatalogEntryFromApi(e)).toList();
        StaffState.instance.mergeVitalCatalog(entries);
      });

  Future<void> _syncMessages() => _try(() async {
        final rows = await AdminApi.instance.listConversations();
        final currentUserId = AuthState.instance.user?.id;
        final conversations = <Conversation>[];
        final threads = <String, List<ChatMessage>>{};
        for (final raw in rows) {
          final conv = PatientDomainMapper.conversationFromApi(
            raw,
            currentUserId: currentUserId,
          );
          conversations.add(conv);
          final last = raw['last_message'] as Map<String, dynamic>?;
          threads[conv.id] = last == null
              ? const []
              : [
                  PatientDomainMapper.messageFromApi(
                    last,
                    currentUserId: currentUserId,
                  ),
                ];
        }
        MessagesState.instance.seed(
          conversations: conversations,
          threads: threads,
        );
      });

  Future<void> _syncSupportTickets() => _try(() async {
        final rows = await AdminApi.instance.listSupportTickets();
        final tickets =
            rows.map((e) => PatientDomainMapper.supportTicketFromApi(e)).toList();
        SupportState.instance.seed(tickets);
      });

  Future<void> _syncAlerts() => _try(() async {
        final rows = await AdminApi.instance.listAlerts();
        final alerts =
            rows.map((e) => StaffMapper.alertFromApi(e)).toList();
        StaffState.instance.mergeAlerts(alerts);
      });

  Future<void> _syncNotifications() => _try(() async {
        final rows = await AdminApi.instance.listNotifications();
        final items = rows
            .map((e) => PatientDomainMapper.notificationFromApi(
                  (e as Map).cast<String, dynamic>(),
                ))
            .toList();
        NotificationState.instance.mergeAdminApiNotifications(items);
      });

  void _applySessionPayload(Map<String, dynamic> session) {
    final users = session['users'] as List?;
    if (users != null) {
      StaffState.instance.mergeUsers(users
          .map((e) => StaffMapper.directoryUserFromApiFull(
                (e as Map).cast<String, dynamic>(),
              ))
          .toList());
    }

    final approvals = session['approvals'] as List?;
    if (approvals != null) {
      StaffState.instance.mergeApprovals(
        approvals.map((e) => StaffMapper.approvalFromApi(
              (e as Map).cast<String, dynamic>(),
            )).toList(),
      );
    }

    final careRequests = session['care_requests'] as List?;
    if (careRequests != null) {
      StaffState.instance.mergeCareRequests(
        careRequests.map((e) => StaffMapper.careRequestFromApi(
              (e as Map).cast<String, dynamic>(),
            )).toList(),
      );
    }

    final assignments = session['assignments'] as List?;
    if (assignments != null) {
      StaffState.instance.mergeAssignments(
        assignments.map((e) => StaffMapper.assignmentFromApi(
              (e as Map).cast<String, dynamic>(),
            )).toList(),
      );
    }

    final audit = session['audit'] as List?;
    if (audit != null) {
      StaffState.instance.mergeAudit(
        audit.map((e) => StaffMapper.auditFromApi(
              (e as Map).cast<String, dynamic>(),
            )).toList(),
      );
    }

    final sos = session['sos_events'] as List?;
    if (sos != null) {
      StaffState.instance.mergeSosEvents(
        sos.map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return StaffMapper.sosFromApi(
            m,
            patientId: (m['patient_id'] ?? '').toString(),
          );
        }).toList(),
      );
    }

    final catalog = session['vital_catalog'] as List?;
    if (catalog != null) {
      StaffState.instance.mergeVitalCatalog(
        catalog.map((e) => StaffMapper.vitalCatalogEntryFromApi(
              (e as Map).cast<String, dynamic>(),
            )).toList(),
      );
    }

    final settings = session['system_settings'] as List?;
    if (settings != null && settings.isNotEmpty) {
      StaffState.instance.mergeSystemSettings(
        settings.map((e) => StaffMapper.systemSettingFromApi(
              (e as Map).cast<String, dynamic>(),
            )).toList(),
      );
    }

    final tickets = session['support_tickets'] as List?;
    if (tickets != null) {
      SupportState.instance.seed(
        tickets
            .map((e) => PatientDomainMapper.supportTicketFromApi(
                  (e as Map).cast<String, dynamic>(),
                ))
            .toList(),
      );
    }

    final alerts = session['alerts'] as List?;
    if (alerts != null) {
      StaffState.instance.mergeAlerts(
        alerts
            .map((e) => StaffMapper.alertFromApi(
                  (e as Map).cast<String, dynamic>(),
                ))
            .toList(),
      );
    }
  }
}

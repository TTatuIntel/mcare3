import '../../core/api/api_client.dart';
import '../../core/api/doctor_api.dart';
import '../../core/api/patient_domain_mapper.dart';
import '../../core/api/staff_mapper.dart';
import '../../core/env/app_env.dart';
import '../auth/auth_state.dart';
import '../models/message.dart';
import '../../core/mock/mock_data.dart';
import '../state/messages_state.dart';
import '../state/notification_state.dart';
import '../state/staff_state.dart';

/// Pulls the doctor session payload from `/doctor/session` and rehydrates
/// `StaffState`. Mock mode short-circuits to the existing `seedDemo()`.
class DoctorSessionService {
  DoctorSessionService._();
  static final DoctorSessionService instance = DoctorSessionService._();

  Future<bool> syncFromApi({bool background = false}) async {
    if (!AppEnv.backendEnabled) {
      if (!AppEnv.demoDataEnabled) return false;
      StaffState.instance.seedDemo();
      MessagesState.instance.seed(
        conversations: MockData.seedDoctorConversations(),
        threads: MockData.seedDoctorMessageThreads(),
      );
      return true;
    }

    try {
      return await _pullSessionFromApi();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _pullSessionFromApi() async {
    final res = await ApiClient.instance.get('/doctor/session');
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    if (data == null) {
      return false;
    }

    final patients = (data['caseload'] as List? ?? const [])
        .map(
          (e) => StaffMapper.patientFromApi((e as Map).cast<String, dynamic>()),
        )
        .toList();
    final alerts = (data['alerts'] as List? ?? const [])
        .map(
          (e) => StaffMapper.alertFromApi((e as Map).cast<String, dynamic>()),
        )
        .toList();
    final appointments = (data['appointments'] as List? ?? const [])
        .map(
          (e) => StaffMapper.appointmentFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
    final prescriptions = (data['prescriptions'] as List? ?? const [])
        .map(
          (e) => StaffMapper.prescriptionFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
    final reports = (data['reports'] as List? ?? const [])
        .map(
          (e) => StaffMapper.reportFromApi((e as Map).cast<String, dynamic>()),
        )
        .toList();
    final vitalRequests = (data['vital_report_requests'] as List? ?? const [])
        .map(
          (e) => StaffMapper.vitalReportRequestFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
    final sosEvents = (data['sos_events'] as List? ?? const []).map((e) {
      final m = (e as Map).cast<String, dynamic>();
      return StaffMapper.sosFromApi(
        m,
        patientId: (m['patient_id'] ?? '').toString(),
      );
    }).toList();
    final vitalCatalog = (data['vital_catalog'] as List? ?? const [])
        .map(
          (e) => StaffMapper.vitalCatalogEntryFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
    final mealPlans = (data['meal_plans'] as List? ?? const [])
        .map(
          (e) =>
              StaffMapper.mealPlanFromApi((e as Map).cast<String, dynamic>()),
        )
        .toList();
    final vitalReadings = (data['vital_readings'] as List? ?? const []).map((
      e,
    ) {
      final m = (e as Map).cast<String, dynamic>();
      return StaffMapper.vitalReadingFromApi(
        m,
        patientId: (m['patient_id'] ?? '').toString(),
      );
    }).toList();

    StaffState.instance.seedFromApi(
      patients: patients,
      alerts: alerts,
      appointments: appointments,
      prescriptions: prescriptions,
      reports: reports,
      vitalRequests: vitalRequests,
      // Triage belongs to admins and mCare assistants; the doctor session
      // deliberately carries no pending care requests.
      careRequests: const [],
      sosEvents: sosEvents,
      vitalCatalog: vitalCatalog,
      mealPlans: mealPlans,
      vitalReadings: vitalReadings,
    );

    final notifications = (data['notifications'] as List? ?? const [])
        .map(
          (e) => PatientDomainMapper.notificationFromApi(
            (e as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
    NotificationState.instance.mergeAdminApiNotifications(notifications);

    await _syncDoctorMessages();
    return true;
  }

  Future<void> _syncDoctorMessages() async {
    if (!AppEnv.backendEnabled) return;
    try {
      final rows = await DoctorApi.instance.listConversations();
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
    } catch (_) {
      // Non-fatal — messages screen can retry on open.
    }
  }
}

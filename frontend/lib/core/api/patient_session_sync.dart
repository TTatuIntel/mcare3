import 'dart:convert';

import '../../shared/auth/auth_state.dart';
import '../../shared/models/message.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/state/care_state.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/state/messages_state.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/state/sos_state.dart';
import '../../shared/state/support_state.dart';
import '../../shared/state/vital_report_state.dart';
import '../../shared/state/vitals_state.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';
import 'patient_profile_mapper.dart';

/// Pulls the full patient session from `GET /patient/session` and seeds
/// all in-memory stores — mirrors MockBootstrap::seedPatientSession().
class PatientSessionSync {
  PatientSessionSync._();
  static final PatientSessionSync instance = PatientSessionSync._();

  String? _lastSignature;

  String _sessionSignature(Map<String, dynamic> data) {
    // Counts alone miss status edits, read receipts, changed appointments and
    // new messages inside an existing conversation. Compare the canonical JSON
    // payload directly so a hash collision cannot hide a clinical update.
    return jsonEncode(data);
  }

  Future<bool> pullFull({bool background = false}) async {
    if (!AppEnv.backendEnabled) {
      return ProfileState.instance.health != null;
    }

    final res = await ApiClient.instance.get('/patient/session');
    final data = res['data'] as Map<String, dynamic>?;
    if (data == null) return false;

    final signature = _sessionSignature(data);
    if (background && signature == _lastSignature) {
      return true;
    }
    _lastSignature = signature;

    final hasProfile = data['has_health_profile'] == true;
    if (!hasProfile) {
      _clearAll(confirmedMissing: true);
      return false;
    }

    final currentUserId = AuthState.instance.user?.id;

    final healthJson = data['health'] as Map<String, dynamic>;
    final contactsJson = data['emergency_contacts'] as List? ?? [];
    final vitalsKeysJson = data['assigned_vitals'] as List? ?? [];

    final health = PatientProfileMapper.healthFromApi(healthJson);
    final contacts = contactsJson
        .map(
          (e) => PatientProfileMapper.contactFromApi(e as Map<String, dynamic>),
        )
        .toList();
    final assigned = vitalsKeysJson
        .map((e) => PatientProfileMapper.vitalKeyFromApi(e as String))
        .toList();

    final trackedKeys = (data['tracked_vitals'] as List? ?? [])
        .map((e) => PatientProfileMapper.vitalKeyFromApi(e as String))
        .toList();

    final catalogKeys = (data['vital_catalog'] as List? ?? [])
        .map(
          (e) => PatientProfileMapper.vitalKeyFromApi(
            ((e as Map<String, dynamic>)['vital'] ?? e['vital_key'] ?? '')
                as String,
          ),
        )
        .toList();

    ProfileState.instance.seed(health: health, contacts: contacts);

    final vitals = (data['vitals'] as List? ?? [])
        .map((e) => PatientDomainMapper.vitalFromApi(e as Map<String, dynamic>))
        .toList();
    VitalsState.instance.seed(vitals);
    VitalsState.instance.seedEnabledCatalog(catalogKeys);
    VitalsState.instance.seedAssigned(assigned);
    if (trackedKeys.isNotEmpty) {
      VitalsState.instance.seedTracked(trackedKeys);
    }

    final meds = (data['medications'] as List? ?? [])
        .map(
          (e) =>
              PatientDomainMapper.medicationFromApi(e as Map<String, dynamic>),
        )
        .toList();
    final medsById = {for (final m in meds) m.id: m};
    final doses = (data['medication_doses'] as List? ?? [])
        .map(
          (e) => PatientDomainMapper.doseFromApi(
            e as Map<String, dynamic>,
            medsById: medsById,
          ),
        )
        .toList();
    MedicationsState.instance.seed(meds: meds, doses: doses);

    final appointments = (data['appointments'] as List? ?? [])
        .map(
          (e) =>
              PatientDomainMapper.appointmentFromApi(e as Map<String, dynamic>),
        )
        .toList();
    AppointmentsState.instance.seed(appointments);

    final documents = (data['documents'] as List? ?? [])
        .map(
          (e) => PatientDomainMapper.documentFromApi(e as Map<String, dynamic>),
        )
        .toList();
    DocumentsState.instance.seed(documents);

    final conversations = <Conversation>[];
    final threads = <String, List<ChatMessage>>{};
    for (final raw in data['conversations'] as List? ?? []) {
      final conv = PatientDomainMapper.conversationFromApi(
        raw as Map<String, dynamic>,
        currentUserId: currentUserId,
      );
      conversations.add(conv);
      threads[conv.id] = [conv.lastMessage];
    }
    MessagesState.instance.seed(conversations: conversations, threads: threads);

    final notifications = (data['notifications'] as List? ?? [])
        .map(
          (e) => PatientDomainMapper.notificationFromApi(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
    NotificationState.instance.seed(notifications);

    final tickets = (data['support_tickets'] as List? ?? [])
        .map(
          (e) => PatientDomainMapper.supportTicketFromApi(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
    SupportState.instance.seed(tickets);

    final sosHistory = (data['sos_history'] as List? ?? [])
        .map(
          (e) => PatientDomainMapper.sosEventFromApi(e as Map<String, dynamic>),
        )
        .toList();
    SosState.instance.seed(contacts: contacts, history: sosHistory);

    final providers = (data['care_providers'] as List? ?? [])
        .map(
          (e) => PatientDomainMapper.careProviderFromApi(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
    final careRequests = (data['care_requests'] as List? ?? [])
        .map(
          (e) =>
              PatientDomainMapper.careRequestFromApi(e as Map<String, dynamic>),
        )
        .toList();
    CareState.instance.seed(providers: providers, requests: careRequests);

    final reportRequests = (data['vital_report_requests'] as List? ?? [])
        .map(
          (e) => PatientDomainMapper.vitalReportRequestFromApi(
            e as Map<String, dynamic>,
          ),
        )
        .toList();
    VitalReportState.instance.seed(reportRequests);

    return true;
  }

  void _clearAll({bool confirmedMissing = false}) {
    ProfileState.instance.clear(confirmedMissing: confirmedMissing);
    VitalsState.instance.seed([]);
    VitalsState.instance.seedAssigned([]);
    MedicationsState.instance.seed(meds: const [], doses: const []);
    AppointmentsState.instance.seed([]);
    DocumentsState.instance.seed([]);
    MessagesState.instance.seed(conversations: const [], threads: const {});
    NotificationState.instance.seed([]);
    SupportState.instance.seed([]);
    SosState.instance.seed(contacts: const [], history: const []);
    CareState.instance.seed(providers: const [], requests: const []);
    VitalReportState.instance.seed([]);
  }
}

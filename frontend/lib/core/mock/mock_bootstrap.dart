import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/announcements_state.dart';
import '../../shared/state/appointments_state.dart';
import '../../shared/state/care_state.dart';
import '../../shared/state/documents_state.dart';
import '../../shared/state/meal_plans_state.dart';
import '../../shared/state/medications_state.dart';
import '../../shared/state/messages_state.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/state/settings_state.dart';
import '../../shared/state/sos_state.dart';
import '../../shared/state/support_state.dart';
import '../api/api_client.dart';
import '../../shared/state/vital_report_state.dart';
import '../../shared/state/vitals_state.dart';
import 'mock_data.dart';

/// Seeds / clears all patient-session mock stores.
class MockBootstrap {
  MockBootstrap._();

  static void seedNewPatientSession({
    required PatientHealthProfile health,
    required List<EmergencyContact> contacts,
    required List<VitalKey> assignedVitals,
  }) {
    VitalsState.instance.seed([]);
    VitalsState.instance.seedAssigned(assignedVitals);
    NotificationState.instance.seed([]);
    VitalReportState.instance.seed([]);
    MedicationsState.instance.seed(meds: [], doses: []);
    AppointmentsState.instance.seed([]);
    DocumentsState.instance.seed([]);
    MessagesState.instance.seed(conversations: [], threads: {});
    CareState.instance.seed(
      providers: MockData.seedCareProviders(),
      requests: [],
    );
    SupportState.instance.seed([]);
    SosState.instance.seed(contacts: contacts, history: []);
    MealPlansState.instance.seed(const []);
    AnnouncementsState.instance.seed(MockData.seedAnnouncements());
    ProfileState.instance.seed(health: health, contacts: contacts);
    SettingsState.instance.seed(notifications: NotificationPreferences());
  }

  static void seedClinicalDemoData() {
    VitalsState.instance.seed(MockData.seedVitals());
    NotificationState.instance.seed(MockData.seedNotifications());
    VitalReportState.instance.seed(MockData.seedVitalReportRequests());
    MedicationsState.instance.seed(
      meds: MockData.seedMedications(),
      doses: MockData.seedAllDoses(),
    );
    AppointmentsState.instance.seed(MockData.seedAppointments());
    DocumentsState.instance.seed(MockData.seedDocuments());
    MessagesState.instance.seed(
      conversations: MockData.seedConversations(),
      threads: MockData.seedMessageThreads(),
    );
    CareState.instance.seed(
      providers: MockData.seedCareProviders(),
      requests: MockData.seedCareRequests(),
    );
    SupportState.instance.seed(MockData.seedSupportTickets());
    MealPlansState.instance.seed(MockData.seedMealPlans());
    AnnouncementsState.instance.seed(MockData.seedAnnouncements());
    SosState.instance.seed(
      contacts: ProfileState.instance.emergencyContacts,
      history: MockData.seedSosHistory(),
    );
    SettingsState.instance.seed(notifications: NotificationPreferences());
  }

  static void seedPatientSession() {
    VitalsState.instance.seed(MockData.seedVitals());
    VitalsState.instance.seedEnabledCatalog(VitalKey.values);
    VitalsState.instance.seedAssigned(MockData.seedAssignedVitals());
    VitalsState.instance.seedTracked([
      VitalKey.bloodPressure,
      VitalKey.heartRate,
      VitalKey.bloodOxygen,
      VitalKey.bloodGlucose,
    ]);
    NotificationState.instance.seed(MockData.seedNotifications());
    VitalReportState.instance.seed(MockData.seedVitalReportRequests());
    MedicationsState.instance.seed(
      meds: MockData.seedMedications(),
      doses: MockData.seedAllDoses(),
    );
    AppointmentsState.instance.seed(MockData.seedAppointments());
    DocumentsState.instance.seed(MockData.seedDocuments());
    MessagesState.instance.seed(
      conversations: MockData.seedConversations(),
      threads: MockData.seedMessageThreads(),
    );
    CareState.instance.seed(
      providers: MockData.seedCareProviders(),
      requests: MockData.seedCareRequests(),
    );
    SupportState.instance.seed(MockData.seedSupportTickets());
    MealPlansState.instance.seed(MockData.seedMealPlans());
    AnnouncementsState.instance.seed(MockData.seedAnnouncements());
    SosState.instance.seed(
      contacts: MockData.seedEmergencyContacts(),
      history: MockData.seedSosHistory(),
    );
    ProfileState.instance.seed(
      health: MockData.seedHealthProfile(),
      contacts: MockData.seedEmergencyContacts(),
    );
    SettingsState.instance.seed(notifications: NotificationPreferences());
  }

  static void clearPatientSession() {
    VitalsState.instance.seed([]);
    VitalsState.instance.seedEnabledCatalog(const []);
    VitalsState.instance.seedAssigned(const []);
    VitalsState.instance.seedTracked(const []);
    NotificationState.instance.seed([]);
    VitalReportState.instance.seed([]);
    MedicationsState.instance.seed(meds: [], doses: []);
    AppointmentsState.instance.seed([]);
    DocumentsState.instance.seed([]);
    MessagesState.instance.seed(conversations: [], threads: {});
    CareState.instance.seed(providers: [], requests: []);
    SupportState.instance.seed([]);
    SosState.instance.seed(contacts: [], history: []);
    MealPlansState.instance.seed(const []);
    AnnouncementsState.instance.seed(const []);
    ProfileState.instance.clear();
    ApiClient.instance.setToken(null);
  }
}

import '../../core/api/api_client.dart';
import '../../core/api/patient_session_sync.dart';
import '../../core/api/patient_profile_mapper.dart';
import '../../core/env/app_env.dart';
import '../../core/mock/mock_bootstrap.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/vital.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/state/vitals_state.dart';
import 'auth_storage.dart';

/// Loads patient profile from API into local state stores.
class PatientSessionService {
  PatientSessionService._();
  static final PatientSessionService instance = PatientSessionService._();

  Future<bool> syncFromApi({bool background = false}) async {
    return PatientSessionSync.instance.pullFull(background: background);
  }

  Future<void> completeOnboarding({
    required PatientHealthProfile health,
    required List<EmergencyContact> contacts,
    required List<VitalKey> assignedVitals,
  }) async {
    if (!AppEnv.backendEnabled) {
      if (!AppEnv.demoDataEnabled) {
        throw StateError('Patient onboarding requires the mCare API.');
      }
      MockBootstrap.seedNewPatientSession(
        health: health,
        contacts: contacts,
        assignedVitals: assignedVitals,
      );
      return;
    }

    await ApiClient.instance.post('/patient/onboarding', body: {
      'health': PatientProfileMapper.healthToApi(health),
      'emergency_contacts':
          contacts.map(PatientProfileMapper.contactToApi).toList(),
      'assigned_vitals': assignedVitals.map((v) => v.name).toList(),
    });

    await syncFromApi();
  }

  /// Updates the health profile and, optionally, the patient's monitoring plan
  /// (assigned vitals). When [assignedVitals] is provided the backend re-syncs
  /// the assigned + tracked vital sets, mirroring onboarding.
  Future<void> updateHealth(
    PatientHealthProfile health, {
    List<VitalKey>? assignedVitals,
  }) async {
    if (!AppEnv.backendEnabled) {
      ProfileState.instance.updateHealth(health);
      if (assignedVitals != null) {
        VitalsState.instance.seedAssigned(assignedVitals);
      }
      return;
    }

    await ApiClient.instance.put('/patient/profile/health', body: {
      ...PatientProfileMapper.healthToApi(health),
      if (assignedVitals != null)
        'assigned_vitals': assignedVitals.map((v) => v.name).toList(),
    });
    ProfileState.instance.updateHealth(health);
    if (assignedVitals != null) {
      VitalsState.instance.seedAssigned(assignedVitals);
    }
  }

  Future<void> updateAccount({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    if (!AppEnv.backendEnabled) return;

    final res = await ApiClient.instance.put('/patient/profile/account', body: {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
    });
    final data = res['data'] as Map<String, dynamic>?;
    final userMap = data?['user'] as Map<String, dynamic>?;
    if (userMap != null) {
      AuthState.instance.updateUser(
        AuthState.instance.user!.copyWith(
          firstName: userMap['first_name'] as String,
          lastName: userMap['last_name'] as String,
          phone: userMap['phone'] as String?,
        ),
      );
      final token = ApiClient.instance.token;
      if (token != null) {
        // Re-saving after a profile edit must not silently promote a
        // browser-session login into a remembered one.
        final stored = await AuthStorage.read();
        await AuthStorage.save(
          token: token,
          user: userMap,
          hasHealthProfile: ProfileState.instance.health != null,
          remember: stored?.remember ?? false,
        );
      }
    }
  }

  /// Profile update for non-patient roles (admin, doctor, mCare assistant).
  /// Hits PUT /auth/profile which has no role restriction.
  Future<void> updateStaffAccount({
    required String firstName,
    required String lastName,
    required String phone,
    String? specialty,
    String? licenseNumber,
  }) async {
    if (!AppEnv.backendEnabled) {
      final user = AuthState.instance.user;
      if (user == null) return;
      AuthState.instance.updateUser(
        user.copyWith(
          firstName: firstName,
          lastName: lastName,
          phone: phone,
          specialty: specialty,
          licenseNumber: licenseNumber,
        ),
      );
      return;
    }

    final res = await ApiClient.instance.put('/auth/profile', body: {
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      if (specialty != null) 'specialty': specialty,
      if (licenseNumber != null) 'license_number': licenseNumber,
    });
    final data = res['data'] as Map<String, dynamic>?;
    final userMap = data?['user'] as Map<String, dynamic>?;
    if (userMap != null) {
      await AuthState.instance.applyServerUser(userMap);
    }
  }

  Future<EmergencyContact> addEmergencyContact(EmergencyContact contact) async {
    if (!AppEnv.backendEnabled) {
      ProfileState.instance.addEmergencyContact(contact);
      return contact;
    }

    final res = await ApiClient.instance.post('/patient/emergency-contacts', body: {
      'name': contact.name,
      'relationship': contact.relationship,
      'phone': contact.phone,
      if (contact.email != null && contact.email!.isNotEmpty)
        'email': contact.email,
      'priority': contact.priority,
    });
    final data = res['data']?['contact'] as Map<String, dynamic>?;
    final saved = data != null
        ? PatientProfileMapper.contactFromApi(data)
        : contact;
    ProfileState.instance.addEmergencyContact(saved);
    return saved;
  }

  Future<void> removeEmergencyContact(String contactId) async {
    if (!AppEnv.backendEnabled) {
      ProfileState.instance.removeEmergencyContact(contactId);
      return;
    }

    await ApiClient.instance.delete('/patient/emergency-contacts/$contactId');
    ProfileState.instance.removeEmergencyContact(contactId);
  }
}

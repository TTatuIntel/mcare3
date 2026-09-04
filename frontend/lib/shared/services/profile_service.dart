import '../../core/env/app_env.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/constants/route_names.dart';
import '../../shared/models/app_user.dart';
import '../../shared/models/notification_item.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../../shared/navigation/profile_navigation.dart';
import '../../shared/state/notification_state.dart';
import '../../shared/state/profile_state.dart';
import '../../shared/services/patient_session_service.dart';

/// Profile mutations with audit-style notifications for patients and care team.
class ProfileService {
  ProfileService._();

  static bool _isClinician(UserRole role) =>
      role == UserRole.doctor ||
      role == UserRole.admin ||
      role == UserRole.mcareAssistant;

  static Future<void> updateAccount({
    required AppUser editor,
    required String firstName,
    required String lastName,
    required String phone,
    String? specialty,
    String? licenseNumber,
  }) async {
    final user = AuthState.instance.user;
    if (user == null) return;

    final isDoctor = user.role == UserRole.doctor;

    final changes = <String>[];
    if (firstName.trim() != user.firstName) changes.add('First name');
    if (lastName.trim() != user.lastName) changes.add('Last name');
    if (phone.trim() != (user.phone ?? '')) changes.add('Phone');
    if (isDoctor &&
        specialty != null &&
        specialty.trim() != (user.specialty ?? '')) {
      changes.add('Specialty');
    }
    if (isDoctor &&
        licenseNumber != null &&
        licenseNumber.trim() != (user.licenseNumber ?? '')) {
      changes.add('Licence number');
    }

    if (changes.isEmpty) return;

    try {
      if (user.role == UserRole.patient) {
        await PatientSessionService.instance.updateAccount(
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          phone: phone.trim(),
        );
      } else {
        await PatientSessionService.instance.updateStaffAccount(
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          phone: phone.trim(),
          specialty: isDoctor ? (specialty?.trim() ?? '') : null,
          licenseNumber: isDoctor ? (licenseNumber?.trim() ?? '') : null,
        );
      }

      if (!AppEnv.backendEnabled) {
        AuthState.instance.updateUser(
          user.copyWith(
            firstName: firstName.trim(),
            lastName: lastName.trim(),
            phone: phone.trim(),
            specialty: isDoctor ? specialty?.trim() : null,
            licenseNumber: isDoctor ? licenseNumber?.trim() : null,
          ),
        );
      }
    } catch (_) {
      rethrow;
    }

    _notifyProfileChange(
      editor: editor,
      patient: AuthState.instance.user!,
      changedFields: changes,
      summary: changes.join(', '),
    );
  }

  static Future<void> updateHealthProfile({
    required AppUser editor,
    required PatientHealthProfile health,
    List<String>? changedFields,
  }) async {
    final prev = ProfileState.instance.health;
    await PatientSessionService.instance.updateHealth(health);

    final fields = changedFields ?? _diffHealth(prev, health);
    if (fields.isEmpty) return;

    _notifyProfileChange(
      editor: editor,
      patient: AuthState.instance.user!,
      changedFields: fields,
      summary: fields.join(', '),
    );
  }

  /// Updates the patient's monitoring plan (which vitals are tracked).
  static Future<void> updateMonitoring({
    required AppUser editor,
    required List<VitalKey> assignedVitals,
  }) async {
    final health = ProfileState.instance.health;
    if (health == null) return;

    await PatientSessionService.instance.updateHealth(
      health,
      assignedVitals: assignedVitals,
    );

    _notifyProfileChange(
      editor: editor,
      patient: AuthState.instance.user!,
      changedFields: ['Monitoring plan'],
      summary:
          '${assignedVitals.length} vital'
          '${assignedVitals.length == 1 ? '' : 's'} monitored',
    );
  }

  static Future<void> setLocationConsent({
    required AppUser editor,
    required bool value,
  }) async {
    final health = ProfileState.instance.health;
    if (health == null || health.locationConsent == value) return;

    health.locationConsent = value;
    ProfileState.instance.updateHealth(health);

    _notifyProfileChange(
      editor: editor,
      patient: AuthState.instance.user!,
      changedFields: ['SOS location consent'],
      summary: value ? 'Location sharing enabled' : 'Location sharing disabled',
    );
  }

  static Future<void> addEmergencyContact({
    required AppUser editor,
    required EmergencyContact contact,
  }) async {
    await PatientSessionService.instance.addEmergencyContact(contact);

    _notifyProfileChange(
      editor: editor,
      patient: AuthState.instance.user!,
      changedFields: ['Emergency contact added'],
      summary: 'Added ${contact.name}',
    );
  }

  static Future<void> removeEmergencyContact({
    required AppUser editor,
    required String contactId,
    required String contactName,
  }) async {
    await PatientSessionService.instance.removeEmergencyContact(contactId);

    _notifyProfileChange(
      editor: editor,
      patient: AuthState.instance.user!,
      changedFields: ['Emergency contact removed'],
      summary: 'Removed $contactName',
    );
  }

  /// Clinicians, admins, and assistants update a patient chart (mock — same session).
  static Future<void> updateHealthAsClinician({
    required AppUser clinician,
    required PatientHealthProfile health,
    List<String>? changedFields,
  }) async {
    if (!_isClinician(clinician.role)) return;

    final patient = AuthState.instance.user;
    if (patient == null || patient.role != UserRole.patient) return;

    final prev = ProfileState.instance.health;
    ProfileState.instance.updateHealth(health);

    final fields = changedFields ?? _diffHealth(prev, health);
    if (fields.isEmpty) return;

    _notifyProfileChange(
      editor: clinician,
      patient: patient,
      changedFields: fields,
      summary: fields.join(', '),
    );
  }

  static List<String> _diffHealth(
    PatientHealthProfile? prev,
    PatientHealthProfile next,
  ) {
    if (prev == null) return ['Health profile'];

    final changes = <String>[];
    if (prev.bloodType != next.bloodType) changes.add('Blood type');
    if (prev.gender != next.gender) changes.add('Gender');
    if (prev.dateOfBirth != next.dateOfBirth) changes.add('Date of birth');
    if (prev.heightCm != next.heightCm) changes.add('Height');
    if (prev.weightKg != next.weightKg) changes.add('Weight');
    if (prev.address != next.address) changes.add('Address');
    if (prev.allergies.join() != next.allergies.join())
      changes.add('Allergies');
    if (prev.chronicConditions.join() != next.chronicConditions.join()) {
      changes.add('Conditions');
    }
    if (prev.currentMedications.join() != next.currentMedications.join()) {
      changes.add('Medications');
    }
    if (prev.locationConsent != next.locationConsent) {
      changes.add('Location consent');
    }
    if (prev.noKnownAllergies != next.noKnownAllergies) {
      changes.add('Allergy status');
    }
    if (prev.noCurrentMedications != next.noCurrentMedications) {
      changes.add('Medication status');
    }
    return changes;
  }

  static void _notifyProfileChange({
    required AppUser editor,
    required AppUser patient,
    required List<String> changedFields,
    required String summary,
  }) {
    final editorLabel = editor.fullName;
    final isSelf = editor.id == patient.id;
    final now = DateTime.now();

    if (isSelf) {
      final route = ProfileNavigation.profileRouteFor(patient.role);
      NotificationState.instance.add(
        AppNotification(
          id: 'profile_self_${now.millisecondsSinceEpoch}',
          kind: NotificationKind.profile,
          title: 'Profile updated',
          body: patient.role == UserRole.patient
              ? 'You updated: $summary. Your care team has been notified.'
              : 'You updated: $summary.',
          createdAt: now,
          actionRoute: route,
        ),
      );
      if (patient.role == UserRole.patient) {
        NotificationState.instance.add(
          AppNotification(
            id: 'profile_team_${now.millisecondsSinceEpoch}',
            kind: NotificationKind.profile,
            title: '${patient.fullName} updated their profile',
            body: 'Changes: $summary',
            createdAt: now,
            read: true,
            actionRoute: RouteNames.patientProfile,
          ),
        );
      }
    } else {
      NotificationState.instance.add(
        AppNotification(
          id: 'profile_patient_${now.millisecondsSinceEpoch}',
          kind: NotificationKind.profile,
          title: 'Profile updated by $editorLabel',
          body: '${editor.role.label} updated your profile: $summary',
          createdAt: now,
          actionRoute: RouteNames.patientProfile,
        ),
      );
      NotificationState.instance.add(
        AppNotification(
          id: 'profile_staff_${now.millisecondsSinceEpoch}',
          kind: NotificationKind.profile,
          title: 'Patient profile edited',
          body: '$editorLabel updated ${patient.fullName}: $summary',
          createdAt: now,
          read: true,
          actionRoute: RouteNames.patientProfile,
        ),
      );
    }
  }
}

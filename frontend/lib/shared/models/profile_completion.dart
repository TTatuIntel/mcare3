import 'app_user.dart';
import 'patient_profile.dart';
import 'sos.dart';
import 'user_role.dart';
import 'vital.dart';

/// One checklist item contributing to profile completion.
class ProfileCompletionItem {
  const ProfileCompletionItem({
    required this.label,
    required this.complete,
    required this.weight,
  });

  final String label;
  final bool complete;
  final int weight;
}

/// Profile completeness score (0–100) for the heart indicator.
class ProfileCompletionResult {
  const ProfileCompletionResult({required this.percent, required this.items});

  final int percent;
  final List<ProfileCompletionItem> items;

  bool get isComplete => percent >= 100;

  List<ProfileCompletionItem> get incompleteItems =>
      items.where((i) => !i.complete).toList(growable: false);
}

class ProfileCompletion {
  ProfileCompletion._();

  /// Role-aware completion so every user — patient, doctor, admin, assistant —
  /// sees the same "complete your profile" experience with the checklist that
  /// matches the information they were asked for at sign-up / onboarding.
  static ProfileCompletionResult forUser({
    AppUser? user,
    PatientHealthProfile? health,
    List<EmergencyContact> contacts = const [],
    List<VitalKey> assignedVitals = const [],
  }) {
    if (user == null) {
      return const ProfileCompletionResult(percent: 0, items: []);
    }
    if (user.role == UserRole.patient) {
      return _patient(user, health, contacts, assignedVitals);
    }
    return _staff(user);
  }

  /// Legacy patient-only entry point (kept for backwards compatibility).
  static ProfileCompletionResult score({
    AppUser? user,
    PatientHealthProfile? health,
    List<EmergencyContact> contacts = const [],
    List<VitalKey> assignedVitals = const [],
  }) => forUser(
    user: user,
    health: health,
    contacts: contacts,
    assignedVitals: assignedVitals,
  );

  static ProfileCompletionResult _result(List<ProfileCompletionItem> items) {
    final total = items.fold<int>(0, (sum, i) => sum + i.weight);
    final earned = items
        .where((i) => i.complete)
        .fold<int>(0, (sum, i) => sum + i.weight);
    final percent = total == 0 ? 0 : ((earned / total) * 100).round();
    return ProfileCompletionResult(
      percent: percent.clamp(0, 100),
      items: items,
    );
  }

  static ProfileCompletionResult _patient(
    AppUser user,
    PatientHealthProfile? health,
    List<EmergencyContact> contacts,
    List<VitalKey> assignedVitals,
  ) {
    return _result([
      ProfileCompletionItem(
        label: 'Mobile phone',
        complete: user.phone != null && user.phone!.trim().length >= 7,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Date of birth',
        complete: health != null,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Gender',
        complete: health != null,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Blood type',
        complete: health != null && health.bloodType != BloodType.unknown,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Height & weight',
        complete:
            health != null &&
            health.heightCm >= 50 &&
            health.heightCm <= 250 &&
            health.weightKg >= 20 &&
            health.weightKg <= 300,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Home address',
        complete:
            health != null &&
            health.address != null &&
            health.address!.trim().isNotEmpty,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Health conditions',
        complete: health != null && health.chronicConditions.isNotEmpty,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Allergies reviewed',
        complete:
            health != null &&
            (health.allergies.isNotEmpty || health.noKnownAllergies),
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Medications reviewed',
        complete:
            health != null &&
            (health.currentMedications.isNotEmpty ||
                health.noCurrentMedications),
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Emergency contact',
        complete: contacts.isNotEmpty,
        weight: 10,
      ),
      ProfileCompletionItem(
        label: 'Monitoring set up',
        complete: assignedVitals.isNotEmpty,
        weight: 10,
      ),
    ]);
  }

  static ProfileCompletionResult _staff(AppUser user) {
    final items = <ProfileCompletionItem>[
      ProfileCompletionItem(
        label: 'Profile photo',
        complete: user.avatarUrl != null && user.avatarUrl!.trim().isNotEmpty,
        weight: 20,
      ),
      ProfileCompletionItem(
        label: 'Mobile phone',
        complete: user.phone != null && user.phone!.trim().length >= 7,
        weight: 20,
      ),
      ProfileCompletionItem(
        label: 'Verified email',
        complete: user.emailVerified,
        weight: 20,
      ),
    ];
    if (user.role == UserRole.doctor) {
      items.add(
        ProfileCompletionItem(
          label: 'Specialty',
          complete: user.specialty != null && user.specialty!.trim().isNotEmpty,
          weight: 20,
        ),
      );
      items.add(
        ProfileCompletionItem(
          label: 'Licence number',
          complete:
              user.licenseNumber != null &&
              user.licenseNumber!.trim().isNotEmpty,
          weight: 20,
        ),
      );
    }
    return _result(items);
  }
}

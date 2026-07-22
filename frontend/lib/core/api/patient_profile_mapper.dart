import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/vital.dart';

/// Parses API JSON into patient domain models.
class PatientProfileMapper {
  static BloodType bloodTypeFromApi(String? raw) {
    return BloodType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => BloodType.unknown,
    );
  }

  static Gender genderFromApi(String? raw) {
    return Gender.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => Gender.preferNotToSay,
    );
  }

  static VitalKey vitalKeyFromApi(String raw) {
    return VitalKey.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => VitalKey.heartRate,
    );
  }

  static PatientHealthProfile healthFromApi(Map<String, dynamic> json) {
    return PatientHealthProfile(
      bloodType: bloodTypeFromApi(json['blood_type'] as String?),
      gender: genderFromApi(json['gender'] as String?),
      dateOfBirth: DateTime.parse(json['date_of_birth'] as String),
      heightCm: (json['height_cm'] as num).toDouble(),
      weightKg: (json['weight_kg'] as num).toDouble(),
      allergies: List<String>.from(json['allergies'] as List? ?? []),
      chronicConditions:
          List<String>.from(json['chronic_conditions'] as List? ?? []),
      currentMedications:
          List<String>.from(json['current_medications'] as List? ?? []),
      address: json['address'] as String?,
      locationConsent: json['location_consent'] as bool? ?? false,
      noKnownAllergies: json['no_known_allergies'] as bool? ?? false,
      noCurrentMedications: json['no_current_medications'] as bool? ?? false,
    );
  }

  static EmergencyContact contactFromApi(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      priority: json['priority'] as int? ?? 1,
    );
  }

  static Map<String, dynamic> healthToApi(PatientHealthProfile health) {
    return {
      'blood_type': health.bloodType.name,
      'gender': health.gender.name,
      'date_of_birth':
          '${health.dateOfBirth.year.toString().padLeft(4, '0')}-${health.dateOfBirth.month.toString().padLeft(2, '0')}-${health.dateOfBirth.day.toString().padLeft(2, '0')}',
      'height_cm': health.heightCm,
      'weight_kg': health.weightKg,
      'allergies': health.allergies,
      'chronic_conditions': health.chronicConditions,
      'current_medications': health.currentMedications,
      'address': health.address,
      'location_consent': health.locationConsent,
      'no_known_allergies': health.noKnownAllergies,
      'no_current_medications': health.noCurrentMedications,
    };
  }

  static Map<String, dynamic> contactToApi(EmergencyContact contact) {
    return {
      'name': contact.name,
      'relationship': contact.relationship,
      'phone': contact.phone,
      'email': contact.email,
      'priority': contact.priority,
    };
  }
}

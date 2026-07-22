import '../models/vital.dart';

/// Clinical condition options shown during patient onboarding.
/// Each maps to vitals the patient should track (stored for care team / API).
class ChronicConditionOption {
  const ChronicConditionOption({
    required this.id,
    required this.label,
    required this.description,
    required this.recommendedVitals,
  });

  final String id;
  final String label;
  final String description;
  final List<VitalKey> recommendedVitals;
}

/// Canonical condition list — extend when backend catalog is wired.
class ChronicConditionCatalog {
  ChronicConditionCatalog._();

  static const List<ChronicConditionOption> all = [
    ChronicConditionOption(
      id: 'type2_diabetes',
      label: 'Type 2 Diabetes',
      description: 'Blood sugar and weight monitoring',
      recommendedVitals: [
        VitalKey.bloodGlucose,
        VitalKey.weight,
        VitalKey.bloodPressure,
      ],
    ),
    ChronicConditionOption(
      id: 'hypertension',
      label: 'Hypertension',
      description: 'Blood pressure and heart rate',
      recommendedVitals: [
        VitalKey.bloodPressure,
        VitalKey.heartRate,
      ],
    ),
    ChronicConditionOption(
      id: 'heart_disease',
      label: 'Heart disease',
      description: 'Heart rate, blood pressure and oxygen',
      recommendedVitals: [
        VitalKey.heartRate,
        VitalKey.bloodPressure,
        VitalKey.bloodOxygen,
      ],
    ),
    ChronicConditionOption(
      id: 'copd',
      label: 'COPD / Asthma',
      description: 'Oxygen and respiratory rate',
      recommendedVitals: [
        VitalKey.bloodOxygen,
        VitalKey.respiratoryRate,
        VitalKey.heartRate,
      ],
    ),
    ChronicConditionOption(
      id: 'kidney',
      label: 'Kidney disease',
      description: 'Blood pressure and weight',
      recommendedVitals: [
        VitalKey.bloodPressure,
        VitalKey.weight,
      ],
    ),
    ChronicConditionOption(
      id: 'obesity',
      label: 'Obesity / Weight management',
      description: 'Weight, glucose and blood pressure',
      recommendedVitals: [
        VitalKey.weight,
        VitalKey.bloodGlucose,
        VitalKey.bloodPressure,
      ],
    ),
    ChronicConditionOption(
      id: 'pregnancy',
      label: 'Pregnancy',
      description: 'Blood pressure and weight',
      recommendedVitals: [
        VitalKey.bloodPressure,
        VitalKey.weight,
        VitalKey.heartRate,
      ],
    ),
    ChronicConditionOption(
      id: 'general',
      label: 'General wellness',
      description: 'Routine vitals for overall health',
      recommendedVitals: [
        VitalKey.heartRate,
        VitalKey.bloodPressure,
        VitalKey.temperature,
      ],
    ),
  ];

  static ChronicConditionOption? byId(String id) {
    for (final o in all) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Union of recommended vitals for selected condition ids.
  static List<VitalKey> vitalsForConditions(Set<String> conditionIds) {
    final keys = <VitalKey>{};
    for (final id in conditionIds) {
      final opt = byId(id);
      if (opt != null) keys.addAll(opt.recommendedVitals);
    }
    if (keys.isEmpty) {
      keys.addAll([
        VitalKey.heartRate,
        VitalKey.bloodPressure,
      ]);
    }
    return keys.toList();
  }

  static List<String> labelsForIds(Set<String> ids) {
    return ids
        .map((id) => byId(id)?.label)
        .whereType<String>()
        .toList();
  }
}

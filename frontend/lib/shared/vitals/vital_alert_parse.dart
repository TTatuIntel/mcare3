import '../../core/api/patient_profile_mapper.dart';
import '../models/vital.dart';

/// Best-effort vital key resolution from API / notification text.
VitalKey parseVitalFromAlertPayload({
  String? vitalKey,
  String? title,
  String? body,
  String? kind,
}) {
  if (vitalKey != null && vitalKey.isNotEmpty) {
    final isBuiltin = VitalKey.values.any((v) => v.name == vitalKey);
    if (isBuiltin) {
      return PatientProfileMapper.vitalKeyFromApi(vitalKey);
    }
  }

  if (kind == 'sos') return VitalKey.heartRate;

  final text = '${title ?? ''} ${body ?? ''}'.toLowerCase();
  if (text.contains('mg/dl') || text.contains('glucose')) {
    return VitalKey.bloodGlucose;
  }
  if (text.contains('bpm') || text.contains('heart')) {
    return VitalKey.heartRate;
  }
  if (text.contains('spo') || text.contains('oxygen')) {
    return VitalKey.bloodOxygen;
  }
  if (text.contains('°c') || text.contains('temp')) {
    return VitalKey.temperature;
  }
  if (text.contains('/min') || text.contains('resp')) {
    return VitalKey.respiratoryRate;
  }
  if (text.contains('kg') || text.contains('weight')) {
    return VitalKey.weight;
  }
  if (text.contains('pressure') || text.contains('mmhg')) {
    return VitalKey.bloodPressure;
  }
  return VitalKey.bloodPressure;
}

RiskLevel severityFromAlertKind(String? kind, String? severity) {
  if (kind == 'vital_critical' || kind == 'sos') return RiskLevel.critical;
  if (kind == 'vital_warning') return RiskLevel.warning;
  return switch (severity) {
    'critical' => RiskLevel.critical,
    'warning' => RiskLevel.warning,
    'normal' => RiskLevel.normal,
    _ => RiskLevel.unknown,
  };
}

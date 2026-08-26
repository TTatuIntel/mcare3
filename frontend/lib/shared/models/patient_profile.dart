enum BloodType { aPos, aNeg, bPos, bNeg, oPos, oNeg, abPos, abNeg, unknown }

extension BloodTypeX on BloodType {
  String get label => switch (this) {
    BloodType.aPos => 'A+',
    BloodType.aNeg => 'A−',
    BloodType.bPos => 'B+',
    BloodType.bNeg => 'B−',
    BloodType.oPos => 'O+',
    BloodType.oNeg => 'O−',
    BloodType.abPos => 'AB+',
    BloodType.abNeg => 'AB−',
    BloodType.unknown => 'Unknown',
  };
}

enum Gender { female, male, nonBinary, preferNotToSay }

extension GenderX on Gender {
  String get label => switch (this) {
    Gender.female => 'Female',
    Gender.male => 'Male',
    Gender.nonBinary => 'Non-binary',
    Gender.preferNotToSay => 'Prefer not to say',
  };
}

class PatientHealthProfile {
  PatientHealthProfile({
    required this.bloodType,
    required this.gender,
    required this.dateOfBirth,
    required this.heightCm,
    required this.weightKg,
    this.allergies = const [],
    this.chronicConditions = const [],
    this.currentMedications = const [],
    this.address,
    this.locationConsent = false,
    this.noKnownAllergies = false,
    this.noCurrentMedications = false,
  });

  BloodType bloodType;
  Gender gender;
  DateTime dateOfBirth;
  double heightCm;
  double weightKg;
  List<String> allergies;
  List<String> chronicConditions;
  List<String> currentMedications;
  String? address;
  bool locationConsent;

  /// Patient confirmed allergy status (including "none known").
  bool noKnownAllergies;

  /// Patient confirmed medication status (including "none").
  bool noCurrentMedications;

  int get ageYears {
    final now = DateTime.now();
    var age = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    return age;
  }

  double get bmi {
    final m = heightCm / 100;
    if (m <= 0) return 0;
    return weightKg / (m * m);
  }

  String get bmiCategory {
    final v = bmi;
    if (v == 0) return 'Unknown';
    if (v < 18.5) return 'Underweight';
    if (v < 25) return 'Healthy';
    if (v < 30) return 'Overweight';
    return 'Obese';
  }

  /// Rough 0-100 wellness score. Blends BMI, chronic-condition load, and
  /// completeness of the profile so care staff can spot at-risk patients at
  /// a glance. Not a clinical score — a triage heuristic.
  int get healthScore {
    var score = 100.0;

    // BMI band: healthy 18.5–25 is untouched; outside deducts based on distance.
    final v = bmi;
    if (v == 0) {
      score -= 20; // unknown BMI → weight/height missing.
    } else if (v < 16 || v >= 35) {
      score -= 30;
    } else if (v < 18.5 || v >= 30) {
      score -= 20;
    } else if (v < 20 || v >= 25) {
      score -= 8;
    }

    // Chronic conditions: -8 each, capped at -32.
    final chronicPenalty = (chronicConditions.length * 8).clamp(0, 32);
    score -= chronicPenalty;

    // Age band: older patients carry more risk by default.
    final age = ageYears;
    if (age >= 75) {
      score -= 10;
    } else if (age >= 60) {
      score -= 5;
    }

    // Profile completeness (small, so gaps nudge but don't dominate).
    if (address == null || address!.trim().isEmpty) score -= 3;
    if (!noKnownAllergies && allergies.isEmpty) score -= 4;
    if (!noCurrentMedications && currentMedications.isEmpty) score -= 4;

    return score.clamp(0, 100).round();
  }

  /// Bucket label for [healthScore] — surface on the profile UI.
  String get healthCategory {
    final s = healthScore;
    if (s >= 85) return 'Excellent';
    if (s >= 70) return 'Good';
    if (s >= 55) return 'Fair';
    if (s >= 40) return 'Watch';
    return 'At risk';
  }
}

class NotificationPreferences {
  NotificationPreferences({
    this.vitalAlerts = true,
    this.appointmentReminders = true,
    this.medicationReminders = true,
    this.messages = true,
    this.reports = true,
    this.pushEnabled = true,
    this.smsEnabled = true,
    this.emailEnabled = true,
  });

  bool vitalAlerts;
  bool appointmentReminders;
  bool medicationReminders;
  bool messages;
  bool reports;
  bool pushEnabled;
  bool smsEnabled;
  bool emailEnabled;

  Map<String, dynamic> toJson() => {
    'vitalAlerts': vitalAlerts,
    'appointmentReminders': appointmentReminders,
    'medicationReminders': medicationReminders,
    'messages': messages,
    'reports': reports,
    'pushEnabled': pushEnabled,
    'smsEnabled': smsEnabled,
    'emailEnabled': emailEnabled,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      vitalAlerts: json['vitalAlerts'] as bool? ?? true,
      appointmentReminders: json['appointmentReminders'] as bool? ?? true,
      medicationReminders: json['medicationReminders'] as bool? ?? true,
      messages: json['messages'] as bool? ?? true,
      reports: json['reports'] as bool? ?? true,
      pushEnabled: json['pushEnabled'] as bool? ?? true,
      smsEnabled: json['smsEnabled'] as bool? ?? true,
      emailEnabled: json['emailEnabled'] as bool? ?? true,
    );
  }

  NotificationPreferences copyWith({
    bool? vitalAlerts,
    bool? appointmentReminders,
    bool? medicationReminders,
    bool? messages,
    bool? reports,
    bool? pushEnabled,
    bool? smsEnabled,
    bool? emailEnabled,
  }) {
    return NotificationPreferences(
      vitalAlerts: vitalAlerts ?? this.vitalAlerts,
      appointmentReminders: appointmentReminders ?? this.appointmentReminders,
      medicationReminders: medicationReminders ?? this.medicationReminders,
      messages: messages ?? this.messages,
      reports: reports ?? this.reports,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      smsEnabled: smsEnabled ?? this.smsEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
    );
  }

  List<bool> get channelValues => [
    vitalAlerts,
    appointmentReminders,
    medicationReminders,
    messages,
    reports,
    pushEnabled,
    smsEnabled,
    emailEnabled,
  ];
}

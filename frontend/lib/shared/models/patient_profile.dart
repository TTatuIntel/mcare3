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
      appointmentReminders:
          appointmentReminders ?? this.appointmentReminders,
      medicationReminders:
          medicationReminders ?? this.medicationReminders,
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

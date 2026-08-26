import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum DoseStatus { pending, taken, skipped, missed }

extension DoseStatusX on DoseStatus {
  String get label => switch (this) {
    DoseStatus.pending => 'Pending',
    DoseStatus.taken => 'Taken',
    DoseStatus.skipped => 'Skipped',
    DoseStatus.missed => 'Missed',
  };

  Color get color => switch (this) {
    DoseStatus.pending => AppColors.info,
    DoseStatus.taken => AppColors.success,
    DoseStatus.skipped => AppColors.warning,
    DoseStatus.missed => AppColors.critical,
  };
}

enum DosePeriod { morning, afternoon, evening, night }

extension DosePeriodX on DosePeriod {
  String get label => switch (this) {
    DosePeriod.morning => 'Morning',
    DosePeriod.afternoon => 'Afternoon',
    DosePeriod.evening => 'Evening',
    DosePeriod.night => 'Night',
  };

  IconData get icon => switch (this) {
    DosePeriod.morning => Icons.wb_sunny_rounded,
    DosePeriod.afternoon => Icons.wb_cloudy_rounded,
    DosePeriod.evening => Icons.wb_twilight_rounded,
    DosePeriod.night => Icons.nightlight_round,
  };

  static DosePeriod fromHour(int h) {
    if (h < 12) return DosePeriod.morning;
    if (h < 17) return DosePeriod.afternoon;
    if (h < 21) return DosePeriod.evening;
    return DosePeriod.night;
  }
}

enum MedicationSource { doctorPrescribed, patientAdded }

extension MedicationSourceX on MedicationSource {
  String get label => switch (this) {
    MedicationSource.doctorPrescribed => 'Prescribed',
    MedicationSource.patientAdded => 'Yours',
  };

  Color get color => switch (this) {
    MedicationSource.doctorPrescribed => AppColors.brandIndigo,
    MedicationSource.patientAdded => AppColors.glucoseAmber,
  };
}

enum MedicationAlertKind { refillLow, expiringSoon, expired }

class MedicationAlert {
  const MedicationAlert({
    required this.medicationId,
    required this.kind,
    required this.title,
    required this.body,
  });

  final String medicationId;
  final MedicationAlertKind kind;
  final String title;
  final String body;

  Color get tint => switch (kind) {
    MedicationAlertKind.refillLow => AppColors.warning,
    MedicationAlertKind.expiringSoon => AppColors.warning,
    MedicationAlertKind.expired => AppColors.critical,
  };
}

class Medication {
  const Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.form,
    this.instructions,
    required this.prescribedBy,
    required this.startDate,
    this.endDate,
    this.active = true,
    this.refillsLeft,
    this.expiryDate,
    this.source = MedicationSource.doctorPrescribed,
  });

  final String id;
  final String name;
  final String dosage; // "500 mg"
  final String frequency; // "Twice a day"
  final String form; // "Tablet", "Capsule", "Syrup"
  final String? instructions; // "Take with food"
  final String prescribedBy;
  final DateTime startDate;
  final DateTime? endDate;
  final bool active;
  final int? refillsLeft;
  final DateTime? expiryDate;
  final MedicationSource source;

  bool get isRefillLow => refillsLeft != null && refillsLeft! <= 1;

  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final days = expiryDate!.difference(DateTime.now()).inDays;
    return days >= 0 && days <= 14;
  }

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  MedicationAlert? get alert {
    if (isExpired) {
      return MedicationAlert(
        medicationId: id,
        kind: MedicationAlertKind.expired,
        title: '$name has expired',
        body: 'Check with your care team before taking.',
      );
    }
    if (isRefillLow) {
      return MedicationAlert(
        medicationId: id,
        kind: MedicationAlertKind.refillLow,
        title: '$name refill needed',
        body: refillsLeft == 0
            ? 'No refills left — request a renewal.'
            : '$refillsLeft refill${refillsLeft == 1 ? '' : 's'} left.',
      );
    }
    if (isExpiringSoon) {
      final days = expiryDate!.difference(DateTime.now()).inDays;
      return MedicationAlert(
        medicationId: id,
        kind: MedicationAlertKind.expiringSoon,
        title: '$name expiring soon',
        body: 'Expires in $days day${days == 1 ? '' : 's'}.',
      );
    }
    return null;
  }
}

class MedicationDose {
  const MedicationDose({
    required this.id,
    required this.medicationId,
    required this.name,
    required this.dosage,
    required this.scheduledAt,
    required this.status,
    this.takenAt,
    this.instructions,
  });

  final String id;
  final String medicationId;
  final String name;
  final String dosage;
  final DateTime scheduledAt;
  final DoseStatus status;
  final DateTime? takenAt;
  final String? instructions;

  DosePeriod get period => DosePeriodX.fromHour(scheduledAt.hour);

  MedicationDose copyWith({DoseStatus? status, DateTime? takenAt}) =>
      MedicationDose(
        id: id,
        medicationId: medicationId,
        name: name,
        dosage: dosage,
        scheduledAt: scheduledAt,
        status: status ?? this.status,
        takenAt: takenAt ?? this.takenAt,
        instructions: instructions,
      );
}

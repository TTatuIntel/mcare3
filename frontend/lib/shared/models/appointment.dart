import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';

enum AppointmentType { inPerson, virtual, phone }

enum AppointmentStatus { scheduled, confirmed, completed, cancelled }

extension AppointmentTypeX on AppointmentType {
  String get label => switch (this) {
    AppointmentType.inPerson => 'In-person',
    AppointmentType.virtual => 'Virtual',
    AppointmentType.phone => 'Phone',
  };

  IconData get icon => switch (this) {
    AppointmentType.inPerson => AppIcons.location,
    AppointmentType.virtual => AppIcons.videocam,
    AppointmentType.phone => AppIcons.phone,
  };
}

extension AppointmentStatusX on AppointmentStatus {
  String get label => switch (this) {
    AppointmentStatus.scheduled => 'Scheduled',
    AppointmentStatus.confirmed => 'Confirmed',
    AppointmentStatus.completed => 'Completed',
    AppointmentStatus.cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    AppointmentStatus.scheduled => AppColors.info,
    AppointmentStatus.confirmed => AppColors.success,
    AppointmentStatus.completed => AppColors.textMutedAA,
    AppointmentStatus.cancelled => AppColors.critical,
  };

  Color get soft => switch (this) {
    AppointmentStatus.scheduled => AppColors.infoSoft,
    AppointmentStatus.confirmed => AppColors.successSoft,
    AppointmentStatus.completed => AppColors.surfaceMuted,
    AppointmentStatus.cancelled => AppColors.criticalSoft,
  };

  /// Theme-aware soft background for status chips.
  Color softBg(BuildContext context) => switch (this) {
    AppointmentStatus.scheduled => AppPalette.infoSoft(context),
    AppointmentStatus.confirmed => AppPalette.successSoft(context),
    AppointmentStatus.completed => AppPalette.surfaceMuted(context),
    AppointmentStatus.cancelled => AppPalette.criticalSoft(context),
  };
}

class Appointment {
  const Appointment({
    required this.id,
    required this.doctorId,
    required this.doctorName,
    required this.doctorSpecialty,
    required this.scheduledAt,
    required this.type,
    required this.status,
    this.reason,
    this.locationOrLink,
    this.durationMinutes = 30,
    this.cancellationReason,
  });

  final String id;
  final String doctorId;
  final String doctorName;
  final String doctorSpecialty;
  final DateTime scheduledAt;
  final AppointmentType type;
  final AppointmentStatus status;
  final String? reason;
  final String? locationOrLink;
  final int durationMinutes;
  final String? cancellationReason;

  bool get isUpcoming =>
      scheduledAt.isAfter(DateTime.now()) &&
      status != AppointmentStatus.cancelled &&
      status != AppointmentStatus.completed;

  Appointment copyWith({
    AppointmentStatus? status,
    String? cancellationReason,
    DateTime? scheduledAt,
  }) => Appointment(
    id: id,
    doctorId: doctorId,
    doctorName: doctorName,
    doctorSpecialty: doctorSpecialty,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    type: type,
    status: status ?? this.status,
    reason: reason,
    locationOrLink: locationOrLink,
    durationMinutes: durationMinutes,
    cancellationReason: cancellationReason ?? this.cancellationReason,
  );
}

import 'package:flutter/material.dart';
import '../../shared/widgets/app_icons.dart';

import '../theme/app_colors.dart';

enum EmergencyKind { medical, accident, fall, panic, other }

extension EmergencyKindX on EmergencyKind {
  String get label => switch (this) {
    EmergencyKind.medical => 'Medical emergency',
    EmergencyKind.accident => 'Accident',
    EmergencyKind.fall => 'Fall',
    EmergencyKind.panic => 'Panic',
    EmergencyKind.other => 'Other',
  };

  IconData get icon => switch (this) {
    EmergencyKind.medical => AppIcons.careTeam,
    EmergencyKind.accident => Icons.car_crash_rounded,
    EmergencyKind.fall => Icons.accessibility_new_rounded,
    EmergencyKind.panic => Icons.bolt_rounded,
    EmergencyKind.other => Icons.warning_rounded,
  };
}

enum SosStatus { active, acknowledged, resolved, falseAlarm }

extension SosStatusX on SosStatus {
  String get label => switch (this) {
    SosStatus.active => 'Active',
    SosStatus.acknowledged => 'Acknowledged',
    SosStatus.resolved => 'Resolved',
    SosStatus.falseAlarm => 'False alarm',
  };

  Color get color => switch (this) {
    SosStatus.active => AppColors.critical,
    SosStatus.acknowledged => AppColors.warning,
    SosStatus.resolved => AppColors.success,
    SosStatus.falseAlarm => AppColors.textMutedAA,
  };
}

class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phone,
    this.email,
    this.priority = 1,
  });

  final String id;
  final String name;
  final String relationship;
  final String phone;
  final String? email;
  final int priority;
}

class SosEvent {
  const SosEvent({
    required this.id,
    required this.kind,
    required this.triggeredAt,
    required this.status,
    this.locationLabel,
    this.note,
    this.respondedBy,
  });

  final String id;
  final EmergencyKind kind;
  final DateTime triggeredAt;
  final SosStatus status;
  final String? locationLabel;
  final String? note;
  final String? respondedBy;
}

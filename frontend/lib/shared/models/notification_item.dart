import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';
import 'vital.dart';

enum NotificationKind {
  vitalAlert,
  appointment,
  medication,
  message,
  support,
  document,
  report,
  careRequest,
  approval,
  sos,
  assignment,
  profile,

  /// Request for the patient to approve disclosure of part of their record.
  consent,

  /// An alert or emergency a clinician has closed, carrying who closed it and
  /// what they decided. Deliberately not a [vitalAlert]: the patient is being
  /// told a problem is over, and dressing that in critical red would make an
  /// answer look like a new emergency.
  resolution,
  system,
}

extension NotificationKindX on NotificationKind {
  IconData get icon => switch (this) {
    NotificationKind.vitalAlert => AppIcons.alert,
    NotificationKind.appointment => AppIcons.appointment,
    NotificationKind.medication => AppIcons.medication,
    NotificationKind.message => AppIcons.chat,
    NotificationKind.support => AppIcons.support,
    NotificationKind.document => AppIcons.document,
    NotificationKind.report => AppIcons.report,
    NotificationKind.careRequest => AppIcons.careTeam,
    NotificationKind.approval => AppIcons.check,
    NotificationKind.sos => AppIcons.sos,
    NotificationKind.assignment => AppIcons.careTeam,
    NotificationKind.profile => AppIcons.user,
    NotificationKind.consent => AppIcons.lock,
    NotificationKind.resolution => AppIcons.check,
    NotificationKind.system => AppIcons.info,
  };

  Color get tint => switch (this) {
    NotificationKind.vitalAlert => AppColors.critical,
    NotificationKind.appointment => AppColors.bpPurple,
    NotificationKind.medication => AppColors.glucoseAmber,
    NotificationKind.message => AppColors.info,
    NotificationKind.support => AppColors.info,
    NotificationKind.document => AppColors.weightSlate,
    NotificationKind.report => AppColors.doctorGreen,
    NotificationKind.careRequest => AppColors.brandIndigo,
    NotificationKind.approval => AppColors.success,
    NotificationKind.sos => AppColors.critical,
    NotificationKind.assignment => AppColors.brandIndigo,
    NotificationKind.profile => AppColors.brandIndigo,
    NotificationKind.consent => AppColors.warning,
    NotificationKind.resolution => AppColors.success,
    NotificationKind.system => AppColors.textMutedAA,
  };
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.resolved = false,
    this.resolvedAt,
    this.actionRoute,
    this.actionArguments,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final bool resolved;
  final DateTime? resolvedAt;
  final String? actionRoute;
  final Object? actionArguments;

  VitalKey? get linkedVital {
    // A resolution notice is about the same vital as the alert it closes, and
    // has to link back to it — otherwise the patient is told a problem was
    // reviewed with no way to see which reading was meant.
    if (kind != NotificationKind.vitalAlert &&
        kind != NotificationKind.resolution) {
      return null;
    }
    final args = actionArguments;
    return args is VitalKey ? args : null;
  }

  AppNotification copyWith({
    bool? read,
    bool? resolved,
    DateTime? resolvedAt,
  }) => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    read: read ?? this.read,
    resolved: resolved ?? this.resolved,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    actionRoute: actionRoute,
    actionArguments: actionArguments,
  );
}

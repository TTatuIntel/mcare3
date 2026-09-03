import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';

/// One line in the life of a request the care team shares.
///
/// The patient sees this as well as staff, which is the whole reason it exists
/// separately from the audit log: a status chip can say "pending" for three
/// days without ever answering "is anyone actually looking at this?".
enum RequestActivityAction {
  opened,
  claimed,
  released,
  escalated,
  resolved,
  declined,
  cancelled,
  note,
}

extension RequestActivityActionX on RequestActivityAction {
  IconData get icon => switch (this) {
    RequestActivityAction.opened => AppIcons.send,
    RequestActivityAction.claimed => AppIcons.acknowledge,
    RequestActivityAction.released => AppIcons.refresh,
    RequestActivityAction.escalated => AppIcons.trendUp,
    RequestActivityAction.resolved => AppIcons.check,
    RequestActivityAction.declined => AppIcons.error,
    RequestActivityAction.cancelled => AppIcons.close,
    RequestActivityAction.note => AppIcons.notes,
  };

  Color get color => switch (this) {
    RequestActivityAction.opened => AppColors.info,
    RequestActivityAction.claimed => AppColors.brandIndigo,
    RequestActivityAction.released => AppColors.warning,
    RequestActivityAction.escalated => AppColors.mcareAmber,
    RequestActivityAction.resolved => AppColors.success,
    RequestActivityAction.declined => AppColors.critical,
    RequestActivityAction.cancelled => AppColors.textMutedAA,
    RequestActivityAction.note => AppColors.textMutedAA,
  };

  /// Reads as `who verb`, so the sentence is built at the call site with the
  /// actor's name in front.
  String get verb => switch (this) {
    RequestActivityAction.opened => 'raised this request',
    RequestActivityAction.claimed => 'took it on',
    RequestActivityAction.released => 'handed it back to the team',
    RequestActivityAction.escalated => 'escalated it to care admin',
    RequestActivityAction.resolved => 'completed it',
    RequestActivityAction.declined => 'could not provide it',
    RequestActivityAction.cancelled => 'withdrew the request',
    RequestActivityAction.note => 'added a note',
  };
}

class RequestActivityEvent {
  const RequestActivityEvent({
    required this.id,
    required this.action,
    required this.actorLabel,
    required this.happenedAt,
    this.note,
  });

  final String id;
  final RequestActivityAction action;

  /// Frozen at write time on the server, so the trail still reads correctly
  /// after a clinician leaves.
  final String actorLabel;
  final DateTime happenedAt;
  final String? note;

  String get sentence => '$actorLabel ${action.verb}';

  static RequestActivityEvent fromApi(Map<String, dynamic> json) =>
      RequestActivityEvent(
        id: (json['id'] ?? '').toString(),
        action: RequestActivityAction.values.firstWhere(
          (a) => a.name == json['action'],
          orElse: () => RequestActivityAction.note,
        ),
        actorLabel: (json['actor_label'] ?? 'Someone') as String,
        happenedAt:
            DateTime.tryParse(
              (json['happened_at'] ?? '') as String,
            )?.toLocal() ??
            DateTime.now(),
        note: json['note'] as String?,
      );

  static List<RequestActivityEvent> listFromApi(Object? raw) =>
      (raw as List? ?? const [])
          .map((e) => fromApi((e as Map).cast<String, dynamic>()))
          .toList(growable: false);
}

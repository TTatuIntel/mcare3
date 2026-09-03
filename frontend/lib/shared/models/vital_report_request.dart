import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';
import 'request_activity_event.dart';
import 'user_role.dart';
import 'vital.dart';

/// `inProgress` is what a claim looks like from the patient's side.
///
/// Before it existed, a request somebody was actively writing up and one
/// nobody had opened both read "Pending", which is the state patients chase
/// the practice about.
enum VitalReportStatus { pending, inProgress, fulfilled, cancelled }

extension VitalReportStatusX on VitalReportStatus {
  String get label => switch (this) {
    VitalReportStatus.pending => 'Waiting',
    VitalReportStatus.inProgress => 'Being prepared',
    VitalReportStatus.fulfilled => 'Ready',
    VitalReportStatus.cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    VitalReportStatus.pending => AppColors.warning,
    VitalReportStatus.inProgress => AppColors.info,
    VitalReportStatus.fulfilled => AppColors.success,
    VitalReportStatus.cancelled => AppColors.textMutedAA,
  };

  IconData get icon => switch (this) {
    VitalReportStatus.pending => AppIcons.time,
    VitalReportStatus.inProgress => AppIcons.acknowledge,
    VitalReportStatus.fulfilled => AppIcons.check,
    VitalReportStatus.cancelled => AppIcons.close,
  };

  bool get isOpen =>
      this == VitalReportStatus.pending || this == VitalReportStatus.inProgress;
}

/// A patient's ask for a summary of their readings over a window.
///
/// Two mechanisms overlap here and they answer different questions. The
/// escalation chain (`currentResponder`) decides who is *answerable* while
/// nobody has picked the request up — doctor → assistant → admin as SLA
/// windows expire. The claim (`claimedByName`) records who is actually *doing
/// it*. A claim wins in every place the two disagree, because someone acting
/// beats someone accountable.
class VitalReportRequest {
  const VitalReportRequest({
    required this.id,
    required this.from,
    required this.to,
    required this.vitals,
    required this.createdAt,
    required this.status,
    required this.currentResponder,
    this.note,
    this.claimedById,
    this.claimedByName,
    this.claimedAt,
    this.waitingOn,
    this.respondedAt,
    this.respondedBy,
    this.responseNote,
    this.resolvedAt,
    this.documentId,
    this.lastEscalatedAt,
    this.events = const [],
  });

  final String id;
  final DateTime from;
  final DateTime to;
  final List<VitalKey> vitals;
  final DateTime createdAt;
  final VitalReportStatus status;
  final UserRole currentResponder;
  final String? note;

  /// The care team member who took this on. Null while it sits in the shared
  /// queue, which is exactly what "nobody has started" looks like.
  final String? claimedById;
  final String? claimedByName;
  final DateTime? claimedAt;

  /// Server-phrased "who you are waiting on", so the app and the care team's
  /// queue never disagree about it.
  final String? waitingOn;

  final DateTime? respondedAt;
  final String? respondedBy;
  final String? responseNote;
  final DateTime? resolvedAt;

  /// The filed report this request produced. Set once it is fulfilled — this
  /// is what makes "Ready" point at something the patient can open, rather
  /// than at a status flag and a note.
  final String? documentId;

  final DateTime? lastEscalatedAt;
  final List<RequestActivityEvent> events;

  bool get isOpen => status.isOpen;
  bool get isPending => status == VitalReportStatus.pending;
  bool get isClaimed => claimedByName != null;

  String get responderLabel {
    if (claimedByName != null) return claimedByName!;
    if (waitingOn != null && waitingOn!.isNotEmpty) return waitingOn!;

    return switch (currentResponder) {
      UserRole.doctor => 'Your care team',
      UserRole.mcareAssistant => 'mCare assistant',
      UserRole.admin => 'Care admin',
      _ => currentResponder.label,
    };
  }

  /// The one line under the date range in a list row.
  String get statusLine => switch (status) {
    VitalReportStatus.pending => 'Waiting on $responderLabel',
    VitalReportStatus.inProgress =>
      '${claimedByName ?? 'Your care team'} is preparing this',
    VitalReportStatus.fulfilled =>
      'Prepared by ${respondedBy ?? 'your care team'}',
    VitalReportStatus.cancelled => 'Cancelled',
  };

  VitalReportRequest copyWith({
    VitalReportStatus? status,
    UserRole? currentResponder,
    String? claimedById,
    String? claimedByName,
    DateTime? claimedAt,
    DateTime? respondedAt,
    String? respondedBy,
    String? responseNote,
    DateTime? resolvedAt,
    String? documentId,
    DateTime? lastEscalatedAt,
    List<RequestActivityEvent>? events,
  }) => VitalReportRequest(
    id: id,
    from: from,
    to: to,
    vitals: vitals,
    createdAt: createdAt,
    status: status ?? this.status,
    currentResponder: currentResponder ?? this.currentResponder,
    note: note,
    claimedById: claimedById ?? this.claimedById,
    claimedByName: claimedByName ?? this.claimedByName,
    claimedAt: claimedAt ?? this.claimedAt,
    waitingOn: waitingOn,
    respondedAt: respondedAt ?? this.respondedAt,
    respondedBy: respondedBy ?? this.respondedBy,
    responseNote: responseNote ?? this.responseNote,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    documentId: documentId ?? this.documentId,
    lastEscalatedAt: lastEscalatedAt ?? this.lastEscalatedAt,
    events: events ?? this.events,
  );
}

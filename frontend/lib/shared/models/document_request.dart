import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';
import 'document.dart';
import 'request_activity_event.dart';

/// What the patient asked for and who they asked.
///
/// `team` reaches every clinician assigned to them; `doctor` names one of
/// them. Both are visible to the whole team — naming a doctor says who it is
/// waiting on, not who is allowed to answer, so a request cannot be stranded
/// behind one person's leave.
enum DocumentRequestTarget { team, doctor }

extension DocumentRequestTargetX on DocumentRequestTarget {
  String get label => switch (this) {
    DocumentRequestTarget.team => 'mCare care team',
    DocumentRequestTarget.doctor => 'A specific doctor',
  };

  IconData get icon => switch (this) {
    DocumentRequestTarget.team => AppIcons.careTeam,
    DocumentRequestTarget.doctor => AppIcons.user,
  };
}

enum DocumentRequestStatus { pending, inProgress, fulfilled, declined, cancelled }

extension DocumentRequestStatusX on DocumentRequestStatus {
  String get label => switch (this) {
    DocumentRequestStatus.pending => 'Waiting',
    DocumentRequestStatus.inProgress => 'Being prepared',
    DocumentRequestStatus.fulfilled => 'Ready',
    DocumentRequestStatus.declined => 'Declined',
    DocumentRequestStatus.cancelled => 'Withdrawn',
  };

  Color get color => switch (this) {
    DocumentRequestStatus.pending => AppColors.warning,
    DocumentRequestStatus.inProgress => AppColors.info,
    DocumentRequestStatus.fulfilled => AppColors.success,
    DocumentRequestStatus.declined => AppColors.critical,
    DocumentRequestStatus.cancelled => AppColors.textMutedAA,
  };

  IconData get icon => switch (this) {
    DocumentRequestStatus.pending => AppIcons.time,
    DocumentRequestStatus.inProgress => AppIcons.acknowledge,
    DocumentRequestStatus.fulfilled => AppIcons.check,
    DocumentRequestStatus.declined => AppIcons.error,
    DocumentRequestStatus.cancelled => AppIcons.close,
  };

  bool get isOpen =>
      this == DocumentRequestStatus.pending ||
      this == DocumentRequestStatus.inProgress;
}

/// A document the patient has asked their care team to produce.
///
/// The mirror of an upload: the record already let files travel from patient
/// to team and from team to patient, but there was no way for the patient to
/// ask for one, so referral letters and copies of old summaries were chased by
/// phone and nothing about the ask was ever recorded.
class DocumentRequest {
  const DocumentRequest({
    required this.id,
    required this.title,
    required this.category,
    required this.target,
    required this.status,
    required this.createdAt,
    this.note,
    this.targetDoctorId,
    this.targetDoctorName,
    this.neededBy,
    this.overdue = false,
    this.claimedByName,
    this.claimedAt,
    this.waitingOn,
    this.resolvedAt,
    this.resolvedByName,
    this.resolutionNote,
    this.declineReason,
    this.documentId,
    this.events = const [],
  });

  final String id;
  final String title;
  final DocumentCategory category;
  final DocumentRequestTarget target;
  final DocumentRequestStatus status;
  final DateTime createdAt;
  final String? note;
  final String? targetDoctorId;
  final String? targetDoctorName;
  final DateTime? neededBy;

  /// Server-decided so the app and the care team's queue agree on what "late"
  /// means, and only ever true while the request is still open.
  final bool overdue;

  /// Who on the care team is doing it. Null while it sits in the shared queue.
  final String? claimedByName;
  final DateTime? claimedAt;

  /// Who the patient is waiting on, already phrased for reading.
  final String? waitingOn;

  final DateTime? resolvedAt;
  final String? resolvedByName;
  final String? resolutionNote;

  /// Why it could not be produced. Shown verbatim: a refusal with no reason is
  /// indistinguishable from being ignored.
  final String? declineReason;

  /// The document that answered it, once there is one.
  final String? documentId;

  final List<RequestActivityEvent> events;

  bool get isOpen => status.isOpen;
  bool get isClaimed => claimedByName != null;

  /// The one line under the title in a list row.
  String get statusLine => switch (status) {
    DocumentRequestStatus.pending =>
      'Waiting on ${waitingOn ?? target.label}',
    DocumentRequestStatus.inProgress =>
      '${claimedByName ?? 'Your care team'} is preparing this',
    DocumentRequestStatus.fulfilled =>
      'Added by ${resolvedByName ?? 'your care team'}',
    DocumentRequestStatus.declined =>
      declineReason ?? 'Your care team could not provide this',
    DocumentRequestStatus.cancelled => 'You withdrew this request',
  };

  DocumentRequest copyWith({
    DocumentRequestStatus? status,
    String? claimedByName,
    DateTime? claimedAt,
    DateTime? resolvedAt,
    List<RequestActivityEvent>? events,
  }) => DocumentRequest(
    id: id,
    title: title,
    category: category,
    target: target,
    status: status ?? this.status,
    createdAt: createdAt,
    note: note,
    targetDoctorId: targetDoctorId,
    targetDoctorName: targetDoctorName,
    neededBy: neededBy,
    overdue: overdue,
    claimedByName: claimedByName ?? this.claimedByName,
    claimedAt: claimedAt ?? this.claimedAt,
    waitingOn: waitingOn,
    resolvedAt: resolvedAt ?? this.resolvedAt,
    resolvedByName: resolvedByName,
    resolutionNote: resolutionNote,
    declineReason: declineReason,
    documentId: documentId,
    events: events ?? this.events,
  );
}

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'user_role.dart';
import 'vital.dart';

enum VitalReportStatus { pending, fulfilled, cancelled }

extension VitalReportStatusX on VitalReportStatus {
  String get label => switch (this) {
    VitalReportStatus.pending => 'Pending',
    VitalReportStatus.fulfilled => 'Ready',
    VitalReportStatus.cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    VitalReportStatus.pending => AppColors.warning,
    VitalReportStatus.fulfilled => AppColors.success,
    VitalReportStatus.cancelled => AppColors.textMutedAA,
  };
}

/// Who must respond next. Escalates doctor → assistant → admin when
/// the current responder does not act within the SLA window.
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
    this.respondedAt,
    this.respondedBy,
    this.responseNote,
    this.lastEscalatedAt,
  });

  final String id;
  final DateTime from;
  final DateTime to;
  final List<VitalKey> vitals;
  final DateTime createdAt;
  final VitalReportStatus status;
  final UserRole currentResponder;
  final String? note;
  final DateTime? respondedAt;
  final String? respondedBy;
  final String? responseNote;
  final DateTime? lastEscalatedAt;

  bool get isPending => status == VitalReportStatus.pending;

  String get responderLabel => switch (currentResponder) {
    UserRole.doctor => 'Your doctor',
    UserRole.mcareAssistant => 'mCare assistant',
    UserRole.admin => 'Care admin',
    _ => currentResponder.label,
  };

  VitalReportRequest copyWith({
    VitalReportStatus? status,
    UserRole? currentResponder,
    DateTime? respondedAt,
    String? respondedBy,
    String? responseNote,
    DateTime? lastEscalatedAt,
  }) => VitalReportRequest(
    id: id,
    from: from,
    to: to,
    vitals: vitals,
    createdAt: createdAt,
    status: status ?? this.status,
    currentResponder: currentResponder ?? this.currentResponder,
    note: note,
    respondedAt: respondedAt ?? this.respondedAt,
    respondedBy: respondedBy ?? this.respondedBy,
    responseNote: responseNote ?? this.responseNote,
    lastEscalatedAt: lastEscalatedAt ?? this.lastEscalatedAt,
  );
}

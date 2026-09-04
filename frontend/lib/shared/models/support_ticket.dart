import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum TicketStatus { open, inProgress, resolved, closed }

enum TicketPriority { low, normal, high, urgent }

enum TicketCategory { technical, medical, billing, account, other }

extension TicketStatusX on TicketStatus {
  String get label => switch (this) {
    TicketStatus.open => 'Open',
    TicketStatus.inProgress => 'In progress',
    TicketStatus.resolved => 'Resolved',
    TicketStatus.closed => 'Closed',
  };

  Color get color => switch (this) {
    TicketStatus.open => AppColors.info,
    TicketStatus.inProgress => AppColors.warning,
    TicketStatus.resolved => AppColors.success,
    TicketStatus.closed => AppColors.textMutedAA,
  };

  Color get soft => switch (this) {
    TicketStatus.open => AppColors.infoSoft,
    TicketStatus.inProgress => AppColors.warningSoft,
    TicketStatus.resolved => AppColors.successSoft,
    TicketStatus.closed => AppColors.surfaceMuted,
  };

  /// Theme-aware soft background for status chips.
  Color softBg(BuildContext context) => switch (this) {
    TicketStatus.open => AppPalette.infoSoft(context),
    TicketStatus.inProgress => AppPalette.warningSoft(context),
    TicketStatus.resolved => AppPalette.successSoft(context),
    TicketStatus.closed => AppPalette.surfaceMuted(context),
  };
}

extension TicketPriorityX on TicketPriority {
  String get label => switch (this) {
    TicketPriority.low => 'Low',
    TicketPriority.normal => 'Normal',
    TicketPriority.high => 'High',
    TicketPriority.urgent => 'Urgent',
  };

  Color get color => switch (this) {
    TicketPriority.low => AppColors.textMutedAA,
    TicketPriority.normal => AppColors.info,
    TicketPriority.high => AppColors.warning,
    TicketPriority.urgent => AppColors.critical,
  };
}

extension TicketCategoryX on TicketCategory {
  String get label => switch (this) {
    TicketCategory.technical => 'Technical',
    TicketCategory.medical => 'Medical',
    TicketCategory.billing => 'Billing',
    TicketCategory.account => 'Account',
    TicketCategory.other => 'Other',
  };
}

class TicketReply {
  const TicketReply({
    required this.id,
    required this.author,
    required this.body,
    required this.sentAt,
    required this.isStaff,
  });

  final String id;
  final String author;
  final String body;
  final DateTime sentAt;
  final bool isStaff;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.description,
    required this.category,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.assignedTo,
    this.assignedToName,
    this.patientName,
    this.patientUserId,
    this.replies = const [],
  });

  final String id;
  final String subject;
  final String description;
  final TicketCategory category;
  final TicketPriority priority;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? assignedTo;
  final String? assignedToName;
  final String? patientName;
  final String? patientUserId;
  final List<TicketReply> replies;

  SupportTicket copyWith({
    TicketStatus? status,
    List<TicketReply>? replies,
    DateTime? updatedAt,
    String? assignedTo,
    String? assignedToName,
  }) => SupportTicket(
    id: id,
    subject: subject,
    description: description,
    category: category,
    priority: priority,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    assignedTo: assignedTo ?? this.assignedTo,
    assignedToName: assignedToName ?? this.assignedToName,
    patientName: patientName,
    patientUserId: patientUserId,
    replies: replies ?? this.replies,
  );
}

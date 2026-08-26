import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum CareRequestStatus { pending, approved, rejected, cancelled }

extension CareRequestStatusX on CareRequestStatus {
  String get label => switch (this) {
    CareRequestStatus.pending => 'Pending',
    CareRequestStatus.approved => 'Approved',
    CareRequestStatus.rejected => 'Rejected',
    CareRequestStatus.cancelled => 'Cancelled',
  };

  Color get color => switch (this) {
    CareRequestStatus.pending => AppColors.warning,
    CareRequestStatus.approved => AppColors.success,
    CareRequestStatus.rejected => AppColors.critical,
    CareRequestStatus.cancelled => AppColors.textMutedAA,
  };
}

class CareProvider {
  const CareProvider({
    required this.id,
    required this.name,
    required this.specialty,
    required this.facility,
    required this.yearsExperience,
    required this.rating,
    required this.totalReviews,
    this.bio,
    this.languages = const ['English'],
    this.assigned = false,
  });

  final String id;
  final String name;
  final String specialty;
  final String facility;
  final int yearsExperience;
  final double rating;
  final int totalReviews;
  final String? bio;
  final List<String> languages;
  final bool assigned;
}

class CareRequest {
  const CareRequest({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.providerSpecialty,
    required this.createdAt,
    required this.status,
    this.reason,
  });

  final String id;
  final String providerId;
  final String providerName;
  final String providerSpecialty;
  final DateTime createdAt;
  final CareRequestStatus status;
  final String? reason;
}

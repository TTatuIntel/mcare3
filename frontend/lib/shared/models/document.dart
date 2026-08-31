import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';

enum DocumentCategory {
  labResult,
  prescription,
  imaging,
  discharge,
  consultationNote,
  other,
}

extension DocumentCategoryX on DocumentCategory {
  String get label => switch (this) {
    DocumentCategory.labResult => 'Lab result',
    DocumentCategory.prescription => 'Prescription',
    DocumentCategory.imaging => 'Imaging',
    DocumentCategory.discharge => 'Discharge',
    DocumentCategory.consultationNote => 'Consultation note',
    DocumentCategory.other => 'Other',
  };

  Color get color => switch (this) {
    DocumentCategory.labResult => AppColors.spo2Blue,
    DocumentCategory.prescription => AppColors.glucoseAmber,
    DocumentCategory.imaging => AppColors.bpPurple,
    DocumentCategory.discharge => AppColors.doctorGreen,
    DocumentCategory.consultationNote => AppColors.info,
    DocumentCategory.other => AppColors.weightSlate,
  };

  IconData get icon => switch (this) {
    DocumentCategory.labResult => AppIcons.lab,
    DocumentCategory.prescription => AppIcons.medication,
    DocumentCategory.imaging => AppIcons.image,
    DocumentCategory.discharge => AppIcons.nurse,
    DocumentCategory.consultationNote => AppIcons.report,
    DocumentCategory.other => AppIcons.document,
  };
}

enum DocumentFileType { pdf, image, doc, other }

extension DocumentFileTypeX on DocumentFileType {
  String get label => switch (this) {
    DocumentFileType.pdf => 'PDF',
    DocumentFileType.image => 'Image',
    DocumentFileType.doc => 'DOC',
    DocumentFileType.other => 'File',
  };

  IconData get icon => switch (this) {
    DocumentFileType.pdf => AppIcons.pdf,
    DocumentFileType.image => AppIcons.image,
    DocumentFileType.doc => AppIcons.document,
    DocumentFileType.other => AppIcons.file,
  };
}

/// Where a document came from, which is what decides whether it can be
/// removed. A file the patient uploaded is theirs to delete; anything a
/// clinician filed is part of the clinical record, and an issued report is the
/// evidence of a disclosure they consented to. Neither of those goes away.
enum DocumentSource { patient, clinician, report }

extension DocumentSourceX on DocumentSource {
  bool get isDeletable => this == DocumentSource.patient;

  /// Shown where the document came from matters to the reader.
  String? get badge => switch (this) {
    DocumentSource.patient => null,
    DocumentSource.clinician => 'From your care team',
    DocumentSource.report => 'Issued report',
  };
}

class MedicalDocument {
  const MedicalDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.fileType,
    required this.sizeBytes,
    required this.uploadedAt,
    required this.uploadedBy,
    this.description,
    this.sharedWithDoctorId,
    this.hasFile = true,
    this.source = DocumentSource.patient,
    this.issuedReportId,
    this.removalRequested = false,
    this.removalRequestedAt,
    this.removalReason,
    this.removalDeclinedAt,
    this.removalDeclinedReason,
    this.canRequestRemoval = false,
  });

  final String id;
  final String title;
  final DocumentCategory category;
  final DocumentFileType fileType;
  final int sizeBytes;
  final DateTime uploadedAt;
  final String uploadedBy;
  final String? description;
  final String? sharedWithDoctorId;
  final bool hasFile;

  /// Legacy rows carry no source and are treated as patient uploads, which is
  /// what they were.
  final DocumentSource source;

  /// Set when this document is the copy of an issued report.
  final String? issuedReportId;

  /// The patient has asked for this to be taken out and staff have not
  /// answered yet.
  final bool removalRequested;
  final DateTime? removalRequestedAt;

  /// Why the patient wants it gone — staff read this before deciding.
  final String? removalReason;

  /// Set when staff refused, with the reason the patient reads.
  final DateTime? removalDeclinedAt;
  final String? removalDeclinedReason;

  /// Whether asking for removal is open to the patient on this document.
  /// Server-decided: their own uploads they simply delete, and an issued
  /// report is revoked rather than removed.
  final bool canRequestRemoval;

  /// Whether the app should offer a delete control at all. Showing one the
  /// server will always refuse is worse than not showing it.
  bool get canDelete => source.isDeletable;

  /// Staff may delete this — and only because the patient asked them to.
  bool get isRemovableByStaff =>
      source == DocumentSource.clinician && removalRequested;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  MedicalDocument copyWith({
    String? id,
    String? title,
    DocumentCategory? category,
    DocumentFileType? fileType,
    int? sizeBytes,
    DateTime? uploadedAt,
    String? uploadedBy,
    String? description,
    String? sharedWithDoctorId,
    bool? hasFile,
    DocumentSource? source,
    String? issuedReportId,
    bool? removalRequested,
    DateTime? removalRequestedAt,
    String? removalReason,
    DateTime? removalDeclinedAt,
    String? removalDeclinedReason,
    bool? canRequestRemoval,
  }) {
    return MedicalDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      fileType: fileType ?? this.fileType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      description: description ?? this.description,
      sharedWithDoctorId: sharedWithDoctorId ?? this.sharedWithDoctorId,
      hasFile: hasFile ?? this.hasFile,
      source: source ?? this.source,
      issuedReportId: issuedReportId ?? this.issuedReportId,
      removalRequested: removalRequested ?? this.removalRequested,
      removalRequestedAt: removalRequestedAt ?? this.removalRequestedAt,
      removalReason: removalReason ?? this.removalReason,
      removalDeclinedAt: removalDeclinedAt ?? this.removalDeclinedAt,
      removalDeclinedReason:
          removalDeclinedReason ?? this.removalDeclinedReason,
      canRequestRemoval: canRequestRemoval ?? this.canRequestRemoval,
    );
  }
}

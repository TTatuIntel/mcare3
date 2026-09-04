import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_icons.dart';

enum DocumentCategory {
  labResult,
  prescription,
  imaging,
  discharge,
  consultationNote,
<<<<<<< Updated upstream
=======

  /// Issued by the care team from a vital report request. Its own category
  /// rather than "other" because it is the one document a patient goes looking
  /// for by name — they asked for it, so they know it exists.
  vitalReport,

  /// The patient's copy of a customised report issued from their record —
  /// signed by a doctor, approved by an admin, and filed here the moment it
  /// goes out. Same reasoning as [vitalReport]: filed as "other" it was buried
  /// among insurance scans, which is the last place someone asked for a
  /// referral letter at a hospital desk will think to look.
  report,
  referral,
  insurance,
>>>>>>> Stashed changes
  other,
}

extension DocumentCategoryX on DocumentCategory {
  String get label => switch (this) {
    DocumentCategory.labResult => 'Lab result',
    DocumentCategory.prescription => 'Prescription',
    DocumentCategory.imaging => 'Imaging',
    DocumentCategory.discharge => 'Discharge',
    DocumentCategory.consultationNote => 'Consultation note',
<<<<<<< Updated upstream
=======
    DocumentCategory.vitalReport => 'Vital report',
    DocumentCategory.report => 'Medical report',
    DocumentCategory.referral => 'Referral',
    DocumentCategory.insurance => 'Insurance',
>>>>>>> Stashed changes
    DocumentCategory.other => 'Other',
  };

  Color get color => switch (this) {
    DocumentCategory.labResult => AppColors.spo2Blue,
    DocumentCategory.prescription => AppColors.glucoseAmber,
    DocumentCategory.imaging => AppColors.bpPurple,
    DocumentCategory.discharge => AppColors.doctorGreen,
    DocumentCategory.consultationNote => AppColors.info,
<<<<<<< Updated upstream
=======
    DocumentCategory.vitalReport => AppColors.brandIndigo,
    DocumentCategory.report => AppColors.brandIndigo,
    DocumentCategory.referral => AppColors.tempTeal,
    DocumentCategory.insurance => AppColors.adminPurple,
>>>>>>> Stashed changes
    DocumentCategory.other => AppColors.weightSlate,
  };

  IconData get icon => switch (this) {
    DocumentCategory.labResult => AppIcons.lab,
    DocumentCategory.prescription => AppIcons.medication,
    DocumentCategory.imaging => AppIcons.image,
    DocumentCategory.discharge => AppIcons.nurse,
    DocumentCategory.consultationNote => AppIcons.report,
<<<<<<< Updated upstream
=======
    DocumentCategory.vitalReport => AppIcons.vitals,
    DocumentCategory.report => AppIcons.report,
    DocumentCategory.referral => AppIcons.send,
    DocumentCategory.insurance => AppIcons.approval,
>>>>>>> Stashed changes
    DocumentCategory.other => AppIcons.document,
  };
}

extension DocumentCategoryReports on DocumentCategory {
  /// Whether this is a report the care team issued.
  ///
  /// Two categories mean it, because a vital report and a customised record
  /// disclosure come out of different flows — but a patient counting the
  /// reports they hold does not care which flow made them, so every count,
  /// filter and label in the app asks this rather than naming one of them.
  bool get isIssuedReport =>
      this == DocumentCategory.vitalReport || this == DocumentCategory.report;
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
<<<<<<< Updated upstream
=======
    this.mimeType,
    this.downloadName,
    this.source = DocumentSource.patient,
    this.issuedReportId,
    this.removalRequested = false,
    this.removalRequestedAt,
    this.removalReason,
    this.removalDeclinedAt,
    this.removalDeclinedReason,
    this.canRequestRemoval = false,
>>>>>>> Stashed changes
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

<<<<<<< Updated upstream
=======
  /// What the stored file actually is, as recorded by the server when it was
  /// uploaded or generated.
  ///
  /// The app used to derive this from [fileType], a four-value enum that is
  /// enough to pick an icon and nothing like enough to hand a file to a browser
  /// or a share sheet. An issued report is HTML and lands in `other`, so it was
  /// handed over as `application/octet-stream` named `.bin` — the one document
  /// the patient was explicitly told to go and open was the one nothing could.
  final String? mimeType;

  /// The filename this document should arrive under, server-decided. Falls back
  /// to a name derived from the title where an older server does not send one.
  final String? downloadName;

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

>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
=======
    String? mimeType,
    String? downloadName,
    DocumentSource? source,
    String? issuedReportId,
    bool? removalRequested,
    DateTime? removalRequestedAt,
    String? removalReason,
    DateTime? removalDeclinedAt,
    String? removalDeclinedReason,
    bool? canRequestRemoval,
>>>>>>> Stashed changes
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
<<<<<<< Updated upstream
=======
      mimeType: mimeType ?? this.mimeType,
      downloadName: downloadName ?? this.downloadName,
      source: source ?? this.source,
      issuedReportId: issuedReportId ?? this.issuedReportId,
      removalRequested: removalRequested ?? this.removalRequested,
      removalRequestedAt: removalRequestedAt ?? this.removalRequestedAt,
      removalReason: removalReason ?? this.removalReason,
      removalDeclinedAt: removalDeclinedAt ?? this.removalDeclinedAt,
      removalDeclinedReason:
          removalDeclinedReason ?? this.removalDeclinedReason,
      canRequestRemoval: canRequestRemoval ?? this.canRequestRemoval,
>>>>>>> Stashed changes
    );
  }
}

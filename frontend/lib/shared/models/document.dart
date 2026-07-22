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
    );
  }
}

import 'package:flutter/material.dart';

import '../models/appointment.dart';
import '../models/document.dart';
import '../models/patient_profile.dart';
import '../models/sos.dart';
import '../models/user_role.dart';
import '../models/vital.dart';

// Staff-domain DTOs extracted from staff_state.dart (facade split phase 0).

class StaffPatient {
  StaffPatient({
    required this.id,
    required this.name,
    required this.age,
    required this.sex,
    required this.condition,
    required this.risk,
    required this.lastReading,
    required this.assignedDoctor,
    this.unreadAlerts = 0,
  });

  final String id;
  final String name;
  int age;
  String sex;
  String condition;
  RiskLevel risk;
  DateTime lastReading;
  final String assignedDoctor;
  int unreadAlerts;

  /// Age · sex · condition — omits empty segments so UI never shows blank dots.
  String get demographicsLine {
    final parts = <String>[];
    if (age > 0) parts.add('$age');
    final s = sex.trim();
    if (s.isNotEmpty) parts.add(s);
    final c = condition.trim();
    if (c.isNotEmpty) parts.add(c);
    return parts.join(' · ');
  }

  bool get hasCondition => condition.trim().isNotEmpty;
}

class StaffAlert {
  StaffAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.vital,
    required this.value,
    required this.severity,
    required this.createdAt,
    this.kind,
    this.acknowledged = false,
    this.resolved = false,
    this.resolutionNote,
    this.resolutionAction,
    this.resolutionCustomAction,
  });

  final String id;
  final String patientId;
  final String patientName;
  final VitalKey vital;
  final String value;
  final RiskLevel severity;
  final DateTime createdAt;
  final String? kind;
  bool acknowledged;
  bool resolved = false;
  String? resolutionNote;
  String? resolutionAction;
  String? resolutionCustomAction;
}

class StaffPatientDocument {
  StaffPatientDocument({
    required this.id,
    required this.patientId,
    required this.title,
    required this.category,
    required this.uploadedAt,
    this.uploadedBy = 'Patient',
    this.fileType = DocumentFileType.pdf,
    this.description,
    this.hasFile = true,
  });

  final String id;
  final String patientId;
  final String title;
  final String category;
  final DateTime uploadedAt;
  final String uploadedBy;
  final DocumentFileType fileType;
  final String? description;
  final bool hasFile;
}

class StaffPatientSos {
  StaffPatientSos({
    required this.id,
    required this.patientId,
    required this.kind,
    required this.status,
    required this.triggeredAt,
    this.patientName,
    this.locationLabel,
    this.note,
    this.latitude,
    this.longitude,
    this.respondedBy,
  });

  final String id;
  final String patientId;
  final String kind;
  final String status;
  final DateTime triggeredAt;
  final String? patientName;
  final String? locationLabel;
  final String? note;
  final double? latitude;
  final double? longitude;
  final String? respondedBy;

  bool get isActive => status == 'active' || status == 'acknowledged';

  String get kindLabel => switch (kind) {
        'medical' => 'Medical emergency',
        'accident' => 'Accident',
        'fall' => 'Fall',
        'panic' => 'Panic',
        _ => 'Emergency',
      };

  String? get mapsUrl {
    if (latitude != null && longitude != null) {
      return 'https://www.google.com/maps?q=$latitude,$longitude';
    }
    return null;
  }
}

class StaffPatientRequest {
  StaffPatientRequest({
    required this.id,
    required this.patientId,
    required this.type,
    required this.summary,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String patientId;
  final String type;
  final String summary;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}

class StaffPatientVitalReading {
  StaffPatientVitalReading({
    this.id,
    required this.patientId,
    this.patientName,
    required this.vital,
    required this.value,
    required this.risk,
    required this.recordedAt,
    this.note,
  });

  final String? id;
  final String patientId;
  final String? patientName;
  final VitalKey vital;
  final String value;
  final RiskLevel risk;
  final DateTime recordedAt;
  final String? note;
}

/// Read-only clinical profile cached for staff patient views.
class StaffPatientClinicalDetail {
  StaffPatientClinicalDetail({
    required this.patientId,
    required this.name,
    this.uniqueId,
    this.email,
    this.phone,
    this.health,
    this.emergencyContacts = const [],
    this.assignedVitals = const {},
    this.assignedVitalsNote,
    this.approvalStatus,
    this.joinedAt,
  });

  final String patientId;
  final String name;
  final String? uniqueId;
  final String? email;
  final String? phone;
  final PatientHealthProfile? health;
  final List<EmergencyContact> emergencyContacts;
  final Set<VitalKey> assignedVitals;
  final String? assignedVitalsNote;
  final String? approvalStatus;
  final DateTime? joinedAt;

  StaffPatientClinicalDetail copyWith({
    PatientHealthProfile? health,
    List<EmergencyContact>? emergencyContacts,
    Set<VitalKey>? assignedVitals,
    String? assignedVitalsNote,
    bool clearAssignedVitalsNote = false,
  }) {
    return StaffPatientClinicalDetail(
      patientId: patientId,
      name: name,
      uniqueId: uniqueId,
      email: email,
      phone: phone,
      health: health ?? this.health,
      emergencyContacts: emergencyContacts ?? this.emergencyContacts,
      assignedVitals: assignedVitals ?? this.assignedVitals,
      assignedVitalsNote: clearAssignedVitalsNote
          ? null
          : (assignedVitalsNote ?? this.assignedVitalsNote),
      approvalStatus: approvalStatus,
      joinedAt: joinedAt,
    );
  }
}

class StaffPrescription {
  StaffPrescription({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.drug,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.issuedAt,
    this.status = 'Active',
  });

  final String id;
  final String patientId;
  final String patientName;
  final String drug;
  final String dosage;
  final String frequency;
  final String duration;
  final DateTime issuedAt;
  String status;
}

class StaffAppointment {
  StaffAppointment({
    required this.id,
    required this.patientName,
    required this.startAt,
    required this.type,
    this.patientId,
    this.reason,
    this.status = AppointmentStatus.scheduled,
    this.durationMinutes = 30,
    this.locationOrLink,
    this.cancellationReason,
  });

  final String id;
  final String? patientId;
  final String patientName;
  final DateTime startAt;
  final AppointmentType type;
  final String? reason;
  final AppointmentStatus status;
  final int durationMinutes;
  final String? locationOrLink;
  final String? cancellationReason;

  /// Legacy display label used in list subtitles.
  String get kind => type.label;

  IconData get typeIcon => type.icon;

  String get typeLabel => type.label;

  String get statusLabel => status.label;

  Color get statusColor => status.color;

  /// Legacy alias for [reason].
  String? get notes => reason;

  bool get isUpcoming =>
      startAt.isAfter(DateTime.now()) &&
      status != AppointmentStatus.cancelled &&
      status != AppointmentStatus.completed;

  StaffAppointment copyWith({
    DateTime? startAt,
    AppointmentStatus? status,
    String? cancellationReason,
    String? reason,
    String? locationOrLink,
    int? durationMinutes,
  }) =>
      StaffAppointment(
        id: id,
        patientId: patientId,
        patientName: patientName,
        startAt: startAt ?? this.startAt,
        type: type,
        reason: reason ?? this.reason,
        status: status ?? this.status,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        locationOrLink: locationOrLink ?? this.locationOrLink,
        cancellationReason: cancellationReason ?? this.cancellationReason,
      );
}

class ClinicalReport {
  ClinicalReport({
    required this.id,
    required this.patientName,
    required this.title,
    required this.createdAt,
    this.body = '',
    this.published = false,
  });

  final String id;
  final String patientName;
  String title;
  String body;
  final DateTime createdAt;
  bool published;
}

class DirectoryUser {
  DirectoryUser({
    required this.id,
    required this.uniqueId,
    required this.name,
    required this.email,
    required this.role,
    required this.status, // active / pending / suspended
    required this.joinedAt,
    this.specialty,
    this.licenseNumber,
    this.isLocked = false,
    this.lockedUntil,
    this.mustChangePassword = false,
  });

  final String id;
  final String uniqueId;
  String name;
  String email;
  final UserRole role;
  String status;
  final DateTime joinedAt;
  final String? specialty;
  final String? licenseNumber;
  bool isLocked;
  DateTime? lockedUntil;
  bool mustChangePassword;
}

class HealthworkerApproval {
  HealthworkerApproval({
    required this.id,
    required this.name,
    required this.email,
    required this.specialty,
    required this.appliedAt,
    this.licenseNumber,
    this.status = 'pending', // pending / approved / rejected
    this.hasCredentialDocument = false,
    this.credentialDocumentName,
  });

  final String id;
  final String name;
  final String email;
  final String specialty;
  final String? licenseNumber;
  final DateTime appliedAt;
  String status;
  bool hasCredentialDocument;
  String? credentialDocumentName;
}

class CareAssignment {
  CareAssignment({
    required this.id,
    required this.patient,
    required this.provider,
    required this.assignedAt,
    this.role = 'Primary',
    this.patientId,
    this.providerId,
    this.providerUserId,
    this.providerSpecialty,
    this.assignedReason,
    this.assignedByName,
  });

  final String id;
  String patient;
  String provider;
  String role;
  final DateTime assignedAt;

  /// Backend ids — null when seeded from demo data.
  final String? patientId;

  /// `care_providers` row id.
  final String? providerId;

  /// Directory (`users`) id of the provider, when the row is linked.
  final String? providerUserId;

  final String? providerSpecialty;

  /// Why this pairing was made — captured on approval or manual assignment.
  final String? assignedReason;
  final String? assignedByName;
}

class CareRequestItem {
  CareRequestItem({
    required this.id,
    required this.patient,
    required this.providerRequested,
    required this.reason,
    required this.createdAt,
    this.patientId,
    this.status = 'pending',
    this.providerId,
    this.providerSpecialty,
    this.assignedProviderId,
    this.assignedProviderName,
    this.assignmentRole,
    this.decisionNote,
    this.decidedAt,
    this.decidedByName,
    this.reassigned = false,
  });

  final String id;
  final String patient;
  final String providerRequested;
  final String reason;
  final DateTime createdAt;

  /// Backend patient user-ID — null when seeded from demo data.
  final String? patientId;
  String status;

  /// `care_providers` row id the patient asked for.
  final String? providerId;
  final String? providerSpecialty;

  /// Provider actually assigned — differs from [providerId] after a re-route.
  String? assignedProviderId;
  String? assignedProviderName;
  String? assignmentRole;

  /// Staff reason attached to the approval, re-route, or decline.
  String? decisionNote;
  DateTime? decidedAt;
  String? decidedByName;

  /// True when staff approved with a provider other than the requested one.
  bool reassigned;

  /// Name of the provider the patient ends up with — the assigned one when
  /// the request was re-routed, otherwise the requested one.
  String get effectiveProvider =>
      (assignedProviderName?.isNotEmpty ?? false)
          ? assignedProviderName!
          : providerRequested;

  bool get isPending => status == 'pending';
  bool get isDecided => !isPending;
}

/// A single entry in the global vital catalog. Built-in vitals carry a
/// [vital] (VitalKey) so existing screens can still resolve icons/units via
/// the enum. Staff-created custom vitals set [vital] to null and supply
/// [customLabel] / [customUnit] instead.
class VitalCatalogEntry {
  VitalCatalogEntry({
    required this.id,
    this.vital,
    required this.normalMin,
    required this.normalMax,
    required this.warningLow,
    required this.warningHigh,
    required this.criticalLow,
    required this.criticalHigh,
    this.enabled = true,
    this.customLabel,
    this.customUnit,
    this.description,
    VitalAlertConfig? alertConfig,
    this.createdBy = 'system',
    DateTime? createdAt,
    this.updatedBy,
    this.updatedAt,
  })  : alertConfig = alertConfig ?? const VitalAlertConfig(),
        createdAt = createdAt ?? DateTime(2024);

  /// Stable lookup key. For built-in vitals this equals [vital.name];
  /// for custom vitals it is a timestamp-based unique id.
  final String id;

  /// Null for staff-created custom vitals.
  final VitalKey? vital;

  double normalMin;
  double normalMax;
  double warningLow;
  double warningHigh;
  double criticalLow;
  double criticalHigh;
  bool enabled;

  /// Display overrides — only set for custom vitals.
  String? customLabel;
  String? customUnit;

  /// Optional clinical description shown in the catalog detail UI.
  String? description;

  /// Per-vital notification and escalation settings.
  VitalAlertConfig alertConfig;

  String createdBy;
  DateTime createdAt;
  String? updatedBy;
  DateTime? updatedAt;

  /// True when this entry was created by staff (not a built-in VitalKey).
  bool get isCustom => vital == null;

  String get displayLabel => customLabel ?? vital?.label ?? 'Unknown';

  String get displayShortLabel {
    if (customLabel != null) {
      final words = customLabel!.trim().split(RegExp(r'\s+'));
      if (words.length == 1) return customLabel!.substring(0, customLabel!.length.clamp(1, 4)).toUpperCase();
      return words.map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join('');
    }
    return vital?.shortLabel ?? '?';
  }

  String get displayUnit => customUnit ?? vital?.unit ?? '';

  bool get hasSecondaryValue => vital?.hasSecondaryValue ?? false;

  VitalRiskRange toRange() => VitalRiskRange(
        normalMin: normalMin,
        normalMax: normalMax,
        warningLow: warningLow,
        warningHigh: warningHigh,
        criticalLow: criticalLow,
        criticalHigh: criticalHigh,
      );
}

/// Per-patient threshold override. Falls back to [VitalCatalogEntry] when null.
class PatientVitalThreshold {
  PatientVitalThreshold({
    required this.patientId,
    required this.vital,
    required this.normalMin,
    required this.normalMax,
    required this.warningLow,
    required this.warningHigh,
    required this.criticalLow,
    required this.criticalHigh,
    required this.setBy,
    required this.updatedAt,
    this.note,
  });

  final String patientId;
  final VitalKey vital;
  double normalMin;
  double normalMax;
  double warningLow;
  double warningHigh;
  double criticalLow;
  double criticalHigh;
  String setBy;
  DateTime updatedAt;
  String? note;

  VitalRiskRange toRange() => VitalRiskRange(
        normalMin: normalMin,
        normalMax: normalMax,
        warningLow: warningLow,
        warningHigh: warningHigh,
        criticalLow: criticalLow,
        criticalHigh: criticalHigh,
      );
}

class AuditEntry {
  AuditEntry({
    required this.id,
    required this.at,
    required this.actor,
    required this.action,
    required this.target,
    this.category = 'activity', // activity / security
  });

  final String id;
  final DateTime at;
  final String actor;
  final String action;
  final String target;
  final String category;
}

class AnalyticsKpi {
  const AnalyticsKpi({
    required this.label,
    required this.value,
    this.deltaPercent,
    this.helper,
  });

  final String label;
  final String value;
  final double? deltaPercent;
  final String? helper;
}

class SystemConfigSection {
  SystemConfigSection({
    required this.key,
    required this.title,
    required this.description,
    required this.category,
    required this.value,
  });

  final String key;
  final String title;
  final String description;
  final String category;
  bool value;
}

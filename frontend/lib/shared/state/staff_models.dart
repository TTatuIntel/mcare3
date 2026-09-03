import 'package:flutter/material.dart';

import '../../core/location/google_maps_service.dart';

import '../models/appointment.dart';
import '../models/document.dart';
import '../models/patient_profile.dart';
import '../models/request_activity_event.dart';
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
    this.resolvedBy,
    this.acknowledgedBy,
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

  /// The clinician who closed this, as the patient was told it. Kept on the
  /// alert so a colleague reading a closed row knows who to ask about it
  /// without going through the audit log.
  String? resolvedBy;

  /// Who picked this up but has not finished it — the signal that stops two
  /// responders phoning the same patient about the same reading.
  String? acknowledgedBy;
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
    this.source = DocumentSource.patient,
    this.removalRequested = false,
    this.removalReason,
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

  /// Where the document came from, which is what decides whether staff may
  /// ever delete it. Legacy rows carry no source and read as patient uploads.
  final DocumentSource source;

  /// The patient has asked for this to be taken out and nobody has answered.
  final bool removalRequested;

  /// Why they want it gone — staff read this before deciding.
  final String? removalReason;

  /// The one case in which staff may delete: a clinician-filed document the
  /// patient has asked to have removed. The authority is the request, not the
  /// role, so this mirrors the server check rather than the caller's identity.
  bool get isRemovableByStaff =>
      source == DocumentSource.clinician && removalRequested;
}

/// One recorded step in how an emergency was worked, as it rides along with
/// the event itself.
class SosProgressStep {
  const SosProgressStep({
    required this.action,
    required this.label,
    required this.actorName,
    required this.at,
    this.detail,
  });

  final String action;
  final String label;
  final String actorName;
  final DateTime at;
  final String? detail;

  bool get isHandover => action == 'assigned_provider';
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
    this.respondedAt,
    this.resolution,
    this.resolutionLabel,
    this.resolutionNote,
    this.progress = const [],
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
  final DateTime? respondedAt;
  final String? resolution;
  final String? resolutionLabel;
  final String? resolutionNote;

  /// What has actually been done on this emergency, oldest first. Read from
  /// the event payload so a coordinator can follow a case they handed on
  /// without opening it.
  final List<SosProgressStep> progress;

  bool get isActive => status == 'active' || status == 'acknowledged';

  /// Owned by someone, but not finished. This is the state that needs
  /// following up: an emergency handed to a provider sits here until it is
  /// actually closed.
  bool get isInProgress => status == 'acknowledged';

  /// Raised and still nobody's.
  bool get needsResponder => status == 'active';

  bool get isClosed => !isActive;

  /// The provider this emergency was handed to, if it was handed to anyone.
  String? get handedTo {
    for (final step in progress.reversed) {
      if (step.isHandover) return step.detail ?? step.actorName;
    }
    return null;
  }

  SosProgressStep? get lastStep => progress.isEmpty ? null : progress.last;

  /// When the case last moved — a recorded step if there is one, otherwise
  /// the response stamp, otherwise when it was raised.
  DateTime get lastActivityAt => lastStep?.at ?? respondedAt ?? triggeredAt;

  String get statusLabel => switch (status) {
    'active' => 'Needs a responder',
    'acknowledged' => 'In progress',
    'resolved' => 'Resolved',
    'falseAlarm' => 'False alarm',
    _ => status,
  };

  String get kindLabel => switch (kind) {
    'medical' => 'Medical emergency',
    'accident' => 'Accident',
    'fall' => 'Fall',
    'panic' => 'Panic',
    _ => 'Emergency',
  };

  String? get mapsUrl {
    if (latitude != null && longitude != null) {
      return GoogleMapsService.searchUri(latitude!, longitude!).toString();
    }
    return null;
  }

  String? get directionsUrl {
    if (latitude != null && longitude != null) {
      return GoogleMapsService.directionsUri(latitude!, longitude!).toString();
    }
    return null;
  }
}

/// A patient request sitting in the care team's shared queue.
///
/// The whole caseload can see it; exactly one clinician can hold it. Which of
/// those two facts a given row is in is the first thing the inbox has to say,
/// because a request nobody has started and one a colleague is mid-way through
/// need opposite actions from the person looking at it.
class StaffPatientRequest {
  StaffPatientRequest({
    required this.id,
    required this.patientId,
    required this.type,
    required this.summary,
    required this.status,
    required this.createdAt,
    this.patientName,
    this.claimedByName,
    this.claimedAt,
    this.claimedByMe = false,
    this.claimable = true,
    this.documentId,
    this.events = const [],
  });

  final String id;
  final String patientId;
  final String type;
  final String summary;

  /// pending | in_progress | fulfilled | cancelled
  final String status;
  final DateTime createdAt;
  final String? patientName;

  /// Who on the team is working on it. Null while it is unclaimed.
  final String? claimedByName;
  final DateTime? claimedAt;

  /// Server-decided rather than derived from [claimedByName], so the app never
  /// has to guess which of several similarly-named clinicians "me" is.
  final bool claimedByMe;
  final bool claimable;

  /// The report this request produced, once it has been completed.
  final String? documentId;

  final List<RequestActivityEvent> events;

  bool get isPending => status == 'pending';
  bool get isOpen => status == 'pending' || status == 'in_progress';
  bool get isClaimed => claimedByName != null;

  /// Claimed by a colleague — visible, but not this clinician's to finish.
  bool get heldByColleague => isClaimed && !claimedByMe;

  StaffPatientRequest copyWith({
    String? status,
    String? claimedByName,
    DateTime? claimedAt,
    bool? claimedByMe,
    bool? claimable,
    String? documentId,
    List<RequestActivityEvent>? events,
  }) => StaffPatientRequest(
    id: id,
    patientId: patientId,
    type: type,
    summary: summary,
    status: status ?? this.status,
    createdAt: createdAt,
    patientName: patientName,
    claimedByName: claimedByName ?? this.claimedByName,
    claimedAt: claimedAt ?? this.claimedAt,
    claimedByMe: claimedByMe ?? this.claimedByMe,
    claimable: claimable ?? this.claimable,
    documentId: documentId ?? this.documentId,
    events: events ?? this.events,
  );

  /// Clears the claim. [copyWith] cannot express this — passing null there
  /// means "leave it alone", which is the whole point of it everywhere else.
  StaffPatientRequest released() => StaffPatientRequest(
    id: id,
    patientId: patientId,
    type: type,
    summary: summary,
    status: 'pending',
    createdAt: createdAt,
    patientName: patientName,
    claimable: true,
    events: events,
  );
}

/// A document the patient has asked the care team to produce.
///
/// Same shape and same rules as [StaffPatientRequest]; kept separate because
/// answering it means uploading a file, and declining it — with a reason the
/// patient reads — is a first-class outcome that a vital report has no
/// equivalent of.
class StaffDocumentRequest {
  StaffDocumentRequest({
    required this.id,
    required this.patientId,
    required this.title,
    required this.category,
    required this.status,
    required this.createdAt,
    this.patientName,
    this.note,
    this.targetDoctorName,
    this.addressedToMe = false,
    this.neededBy,
    this.overdue = false,
    this.claimedByName,
    this.claimedByMe = false,
    this.claimable = true,
    this.declineReason,
    this.documentId,
    this.events = const [],
  });

  final String id;
  final String patientId;
  final String title;

  /// The camelCase document category key, shared with the patient app.
  final String category;
  final String status;
  final DateTime createdAt;
  final String? patientName;
  final String? note;

  /// Set when the patient named a doctor. That names who it is waiting on, not
  /// who may answer — the whole team still sees it.
  final String? targetDoctorName;
  final bool addressedToMe;

  final DateTime? neededBy;
  final bool overdue;

  final String? claimedByName;
  final bool claimedByMe;
  final bool claimable;

  final String? declineReason;
  final String? documentId;
  final List<RequestActivityEvent> events;

  bool get isOpen => status == 'pending' || status == 'in_progress';
  bool get isClaimed => claimedByName != null;
  bool get heldByColleague => isClaimed && !claimedByMe;

  StaffDocumentRequest copyWith({
    String? status,
    String? claimedByName,
    bool? claimedByMe,
    bool? claimable,
    String? declineReason,
    String? documentId,
    List<RequestActivityEvent>? events,
  }) => StaffDocumentRequest(
    id: id,
    patientId: patientId,
    title: title,
    category: category,
    status: status ?? this.status,
    createdAt: createdAt,
    patientName: patientName,
    note: note,
    targetDoctorName: targetDoctorName,
    addressedToMe: addressedToMe,
    neededBy: neededBy,
    overdue: overdue,
    claimedByName: claimedByName ?? this.claimedByName,
    claimedByMe: claimedByMe ?? this.claimedByMe,
    claimable: claimable ?? this.claimable,
    declineReason: declineReason ?? this.declineReason,
    documentId: documentId ?? this.documentId,
    events: events ?? this.events,
  );

  StaffDocumentRequest released() => StaffDocumentRequest(
    id: id,
    patientId: patientId,
    title: title,
    category: category,
    status: 'pending',
    createdAt: createdAt,
    patientName: patientName,
    note: note,
    targetDoctorName: targetDoctorName,
    addressedToMe: addressedToMe,
    neededBy: neededBy,
    overdue: overdue,
    claimable: true,
    events: events,
  );
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
  }) => StaffAppointment(
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
  String get effectiveProvider => (assignedProviderName?.isNotEmpty ?? false)
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
  }) : alertConfig = alertConfig ?? const VitalAlertConfig(),
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
      if (words.length == 1)
        return customLabel!
            .substring(0, customLabel!.length.clamp(1, 4))
            .toUpperCase();
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

import 'user_role.dart';

/// Complete account record for ANY role, parsed from `/admin/users/{id}/profile`.
///
/// The backend returns one uniform envelope — `account`, `application`,
/// `security`, `stats`, `timeline`, `activity` — plus role-specific blocks
/// (`clinical` + `progress` for patients, `practice` + `access` for staff).
/// Absent blocks parse to null so the UI renders what exists without role
/// branching.
class UserDossier {
  const UserDossier({
    required this.account,
    required this.application,
    required this.security,
    required this.stats,
    required this.timeline,
    required this.activity,
    this.clinical,
    this.progress,
    this.practice,
    this.access,
  });

  final DossierAccount account;
  final DossierApplication application;
  final DossierSecurity security;
  final List<DossierStat> stats;
  final List<DossierEvent> timeline;
  final List<DossierActivity> activity;

  /// Patient-only.
  final DossierClinical? clinical;
  final DossierProgress? progress;

  /// Staff-only (doctor / assistant / admin).
  final DossierPractice? practice;
  final DossierAccess? access;

  bool get isPatient => account.role == UserRole.patient;
  bool get isDoctor => account.role == UserRole.doctor;

  static UserDossier fromJson(Map<String, dynamic> json) {
    return UserDossier(
      account: DossierAccount.fromJson(_map(json['account'])),
      application: DossierApplication.fromJson(_map(json['application'])),
      security: DossierSecurity.fromJson(_map(json['security'])),
      stats: _listOf(json['stats']).map(DossierStat.fromJson).toList(),
      timeline: _listOf(json['timeline']).map(DossierEvent.fromJson).toList(),
      activity:
          _listOf(json['activity']).map(DossierActivity.fromJson).toList(),
      clinical: json['clinical'] is Map
          ? DossierClinical.fromJson(_map(json['clinical']))
          : null,
      progress: json['progress'] is Map
          ? DossierProgress.fromJson(_map(json['progress']))
          : null,
      practice: json['practice'] is Map
          ? DossierPractice.fromJson(_map(json['practice']))
          : null,
      access: json['access'] is Map
          ? DossierAccess.fromJson(_map(json['access']))
          : null,
    );
  }
}

class DossierAccount {
  const DossierAccount({
    required this.id,
    required this.name,
    required this.role,
    this.uniqueId,
    this.firstName,
    this.lastName,
    this.initials = '?',
    this.email,
    this.phone,
    this.avatarUrl,
    this.status = 'active',
    this.profileComplete = false,
    this.emailVerified = false,
    this.emailVerifiedAt,
    this.createdAt,
    this.updatedAt,
    this.accountAgeDays,
  });

  final String id;
  final String name;
  final UserRole role;
  final String? uniqueId;
  final String? firstName;
  final String? lastName;
  final String initials;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final String status;
  final bool profileComplete;
  final bool emailVerified;
  final DateTime? emailVerifiedAt;

  /// Date the account was opened — what staff call "applied" for staff roles.
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? accountAgeDays;

  static DossierAccount fromJson(Map<String, dynamic> j) => DossierAccount(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? 'Unknown'}',
        role: _role(j['role']),
        uniqueId: _str(j['unique_id']),
        firstName: _str(j['first_name']),
        lastName: _str(j['last_name']),
        initials: _str(j['initials']) ?? '?',
        email: _str(j['email']),
        phone: _str(j['phone']),
        avatarUrl: _str(j['avatar_url']),
        status: _str(j['status']) ?? 'active',
        profileComplete: j['profile_complete'] == true,
        emailVerified: j['email_verified'] == true,
        emailVerifiedAt: _date(j['email_verified_at']),
        createdAt: _date(j['created_at']),
        updatedAt: _date(j['updated_at']),
        accountAgeDays: _int(j['account_age_days']),
      );
}

class DossierApplication {
  const DossierApplication({
    this.appliedAt,
    this.specialty,
    this.licenseNumber,
    this.hasCredentialDocument = false,
    this.credentialDocumentName,
    this.approvedAt,
    this.approvedByName,
    this.approvalNote,
    this.rejectedAt,
    this.rejectionReason,
    this.inviteSentAt,
    this.inviteExpiresAt,
    this.inviteAcceptedAt,
    this.invitePending = false,
  });

  final DateTime? appliedAt;
  final String? specialty;
  final String? licenseNumber;
  final bool hasCredentialDocument;
  final String? credentialDocumentName;
  final DateTime? approvedAt;
  final String? approvedByName;
  final String? approvalNote;
  final DateTime? rejectedAt;
  final String? rejectionReason;
  final DateTime? inviteSentAt;
  final DateTime? inviteExpiresAt;
  final DateTime? inviteAcceptedAt;
  final bool invitePending;

  /// True when there is anything worth rendering in the application card.
  bool get hasContent =>
      specialty != null ||
      licenseNumber != null ||
      hasCredentialDocument ||
      approvedAt != null ||
      rejectedAt != null ||
      inviteSentAt != null;

  static DossierApplication fromJson(Map<String, dynamic> j) =>
      DossierApplication(
        appliedAt: _date(j['applied_at']),
        specialty: _str(j['specialty']),
        licenseNumber: _str(j['license_number']),
        hasCredentialDocument: j['has_credential_document'] == true,
        credentialDocumentName: _str(j['credential_document_name']),
        approvedAt: _date(j['approved_at']),
        approvedByName: _str(j['approved_by_name']),
        approvalNote: _str(j['approval_note']),
        rejectedAt: _date(j['rejected_at']),
        rejectionReason: _str(j['rejection_reason']),
        inviteSentAt: _date(j['invite_sent_at']),
        inviteExpiresAt: _date(j['invite_expires_at']),
        inviteAcceptedAt: _date(j['invite_accepted_at']),
        invitePending: j['invite_pending'] == true,
      );
}

class DossierSecurity {
  const DossierSecurity({
    this.lastLoginAt,
    this.lastLoginIp,
    this.loginCount = 0,
    this.mustChangePassword = false,
    this.failedLoginAttempts = 0,
    this.isLocked = false,
    this.lockedUntil,
    this.hasPassword = true,
    this.googleLinked = false,
    this.appleLinked = false,
    this.activeSessions = 0,
    this.lastSessionUsedAt,
    this.pushDevices = 0,
    this.sessions = const [],
  });

  final DateTime? lastLoginAt;
  final String? lastLoginIp;
  final int loginCount;
  final bool mustChangePassword;
  final int failedLoginAttempts;
  final bool isLocked;
  final DateTime? lockedUntil;
  final bool hasPassword;
  final bool googleLinked;
  final bool appleLinked;
  final int activeSessions;
  final DateTime? lastSessionUsedAt;
  final int pushDevices;
  final List<DossierSession> sessions;

  /// "Password · Google" — how this account can actually sign in.
  String get signInMethods {
    final methods = <String>[
      if (hasPassword) 'Password',
      if (googleLinked) 'Google',
      if (appleLinked) 'Apple',
    ];
    return methods.isEmpty ? 'None configured' : methods.join(' · ');
  }

  static DossierSecurity fromJson(Map<String, dynamic> j) => DossierSecurity(
        lastLoginAt: _date(j['last_login_at']),
        lastLoginIp: _str(j['last_login_ip']),
        loginCount: _int(j['login_count']) ?? 0,
        mustChangePassword: j['must_change_password'] == true,
        failedLoginAttempts: _int(j['failed_login_attempts']) ?? 0,
        isLocked: j['is_locked'] == true,
        lockedUntil: _date(j['locked_until']),
        hasPassword: j['has_password'] == true,
        googleLinked: j['google_linked'] == true,
        appleLinked: j['apple_linked'] == true,
        activeSessions: _int(j['active_sessions']) ?? 0,
        lastSessionUsedAt: _date(j['last_session_used_at']),
        pushDevices: _int(j['push_devices']) ?? 0,
        sessions:
            _listOf(j['sessions']).map(DossierSession.fromJson).toList(),
      );
}

class DossierSession {
  const DossierSession({this.name, this.createdAt, this.lastUsedAt});

  final String? name;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  static DossierSession fromJson(Map<String, dynamic> j) => DossierSession(
        name: _str(j['name']),
        createdAt: _date(j['created_at']),
        lastUsedAt: _date(j['last_used_at']),
      );
}

/// One headline number in the dossier's stat strip.
class DossierStat {
  const DossierStat({
    required this.key,
    required this.label,
    required this.value,
    this.tone = 'neutral',
  });

  final String key;
  final String label;
  final String value;

  /// good / warn / bad / neutral — the backend classifies, the UI colours.
  final String tone;

  static DossierStat fromJson(Map<String, dynamic> j) => DossierStat(
        key: '${j['key'] ?? ''}',
        label: '${j['label'] ?? ''}',
        value: '${j['value'] ?? '—'}',
        tone: _str(j['tone']) ?? 'neutral',
      );
}

class DossierEvent {
  const DossierEvent({
    required this.at,
    required this.kind,
    required this.title,
    this.detail,
  });

  final DateTime at;
  final String kind;
  final String title;
  final String? detail;

  static DossierEvent fromJson(Map<String, dynamic> j) => DossierEvent(
        at: _date(j['at']) ?? DateTime.now(),
        kind: _str(j['kind']) ?? 'event',
        title: '${j['title'] ?? ''}',
        detail: _str(j['detail']),
      );
}

class DossierActivity {
  const DossierActivity({
    required this.id,
    required this.at,
    required this.actor,
    required this.action,
    this.target,
    this.category = 'activity',
    this.isActor = false,
  });

  final String id;
  final DateTime at;
  final String actor;
  final String action;
  final String? target;
  final String category;

  /// True when this user performed the action (rather than being its subject).
  final bool isActor;

  static DossierActivity fromJson(Map<String, dynamic> j) => DossierActivity(
        id: '${j['id'] ?? ''}',
        at: _date(j['happened_at']) ?? DateTime.now(),
        actor: '${j['actor'] ?? ''}',
        action: '${j['action'] ?? ''}',
        target: _str(j['target']),
        category: _str(j['category']) ?? 'activity',
        isActor: j['is_actor'] == true,
      );
}

// ---------------------------------------------------------------------------
// Patient blocks
// ---------------------------------------------------------------------------

class DossierClinical {
  const DossierClinical({
    this.health,
    this.hasHealthProfile = false,
    this.emergencyContacts = const [],
    this.assignedVitals = const [],
    this.vitalsSummary = const [],
    this.recentReadings = const [],
    this.medications = const [],
    this.mealPlans = const [],
    this.appointments = const [],
    this.documents = const [],
    this.sosEvents = const [],
    this.reports = const [],
    this.alerts = const [],
    this.careTeam = const [],
    this.careRequests = const [],
    this.vitalReportRequests = const [],
    this.supportTickets = const [],
  });

  /// Raw health-profile map — rendered through the existing
  /// PatientHealthProfile parser so this model stays transport-only.
  final Map<String, dynamic>? health;
  final bool hasHealthProfile;
  final List<Map<String, dynamic>> emergencyContacts;
  final List<String> assignedVitals;
  final List<DossierVitalSummary> vitalsSummary;
  final List<Map<String, dynamic>> recentReadings;
  final List<Map<String, dynamic>> medications;
  final List<Map<String, dynamic>> mealPlans;
  final List<Map<String, dynamic>> appointments;
  final List<Map<String, dynamic>> documents;
  final List<Map<String, dynamic>> sosEvents;
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> alerts;
  final List<Map<String, dynamic>> careTeam;
  final List<Map<String, dynamic>> careRequests;
  final List<Map<String, dynamic>> vitalReportRequests;
  final List<Map<String, dynamic>> supportTickets;

  int get activeMedications =>
      medications.where((m) => m['active'] == true).length;

  static DossierClinical fromJson(Map<String, dynamic> j) => DossierClinical(
        health: j['health'] is Map ? _map(j['health']) : null,
        hasHealthProfile: j['has_health_profile'] == true,
        emergencyContacts: _listOf(j['emergency_contacts']),
        assignedVitals: _strings(j['assigned_vitals']),
        vitalsSummary: _listOf(j['vitals_summary'])
            .map(DossierVitalSummary.fromJson)
            .toList(),
        recentReadings: _listOf(j['recent_readings']),
        medications: _listOf(j['medications']),
        mealPlans: _listOf(j['meal_plans']),
        appointments: _listOf(j['appointments']),
        documents: _listOf(j['documents']),
        sosEvents: _listOf(j['sos_events']),
        reports: _listOf(j['reports']),
        alerts: _listOf(j['alerts']),
        careTeam: _listOf(j['care_team']),
        careRequests: _listOf(j['care_requests']),
        vitalReportRequests: _listOf(j['vital_report_requests']),
        supportTickets: _listOf(j['support_tickets']),
      );
}

class DossierVitalSummary {
  const DossierVitalSummary({
    required this.vitalKey,
    required this.label,
    this.unit = '',
    this.assigned = false,
    this.latestValue,
    this.latestRisk,
    this.latestAt,
    this.readings30d = 0,
    this.readingsTotal = 0,
    this.trend = 'flat',
  });

  final String vitalKey;
  final String label;
  final String unit;
  final bool assigned;
  final String? latestValue;
  final String? latestRisk;
  final DateTime? latestAt;
  final int readings30d;
  final int readingsTotal;

  /// up / down / flat over the last 30 days.
  final String trend;

  static DossierVitalSummary fromJson(Map<String, dynamic> j) =>
      DossierVitalSummary(
        vitalKey: '${j['vital_key'] ?? ''}',
        label: '${j['label'] ?? j['vital_key'] ?? ''}',
        unit: _str(j['unit']) ?? '',
        assigned: j['assigned'] == true,
        latestValue: _str(j['latest_value']),
        latestRisk: _str(j['latest_risk']),
        latestAt: _date(j['latest_at']),
        readings30d: _int(j['readings_30d']) ?? 0,
        readingsTotal: _int(j['readings_total']) ?? 0,
        trend: _str(j['trend']) ?? 'flat',
      );
}

class DossierProgress {
  const DossierProgress({
    this.adherencePercent,
    this.dosesDue30d = 0,
    this.dosesTaken30d = 0,
    this.dosesMissed30d = 0,
    this.readings7d = 0,
    this.readings30d = 0,
    this.loggingStreakDays = 0,
    this.lastReadingAt,
    this.daysSinceLastReading,
    this.appointmentsKept = 0,
    this.appointmentsMissed = 0,
    this.engagementScore = 0,
  });

  final int? adherencePercent;
  final int dosesDue30d;
  final int dosesTaken30d;
  final int dosesMissed30d;
  final int readings7d;
  final int readings30d;
  final int loggingStreakDays;
  final DateTime? lastReadingAt;
  final int? daysSinceLastReading;
  final int appointmentsKept;
  final int appointmentsMissed;
  final int engagementScore;

  static DossierProgress fromJson(Map<String, dynamic> j) => DossierProgress(
        adherencePercent: _int(j['adherence_percent']),
        dosesDue30d: _int(j['doses_due_30d']) ?? 0,
        dosesTaken30d: _int(j['doses_taken_30d']) ?? 0,
        dosesMissed30d: _int(j['doses_missed_30d']) ?? 0,
        readings7d: _int(j['readings_7d']) ?? 0,
        readings30d: _int(j['readings_30d']) ?? 0,
        loggingStreakDays: _int(j['logging_streak_days']) ?? 0,
        lastReadingAt: _date(j['last_reading_at']),
        daysSinceLastReading: _int(j['days_since_last_reading']),
        appointmentsKept: _int(j['appointments_kept']) ?? 0,
        appointmentsMissed: _int(j['appointments_missed']) ?? 0,
        engagementScore: _int(j['engagement_score']) ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Staff blocks
// ---------------------------------------------------------------------------

class DossierPractice {
  const DossierPractice({
    this.provider,
    this.caseloadActive = 0,
    this.caseloadEnded = 0,
    this.caseload = const [],
    this.careRequestsHandled = 0,
    this.careRequestsPending = 0,
    this.prescriptionsIssued = 0,
    this.prescriptionsActive = 0,
    this.reportsAuthored = 0,
    this.reportsPublished = 0,
    this.mealPlansAssigned = 0,
    this.appointmentsTotal = 0,
    this.appointmentsUpcoming = 0,
    this.recentAppointments = const [],
    this.recentReports = const [],
    this.patientsAlerting = 0,
  });

  final Map<String, dynamic>? provider;
  final int caseloadActive;
  final int caseloadEnded;
  final List<Map<String, dynamic>> caseload;
  final int careRequestsHandled;
  final int careRequestsPending;
  final int prescriptionsIssued;
  final int prescriptionsActive;
  final int reportsAuthored;
  final int reportsPublished;
  final int mealPlansAssigned;
  final int appointmentsTotal;
  final int appointmentsUpcoming;
  final List<Map<String, dynamic>> recentAppointments;
  final List<Map<String, dynamic>> recentReports;
  final int patientsAlerting;

  String? get facility => _str(provider?['facility']);
  String? get bio => _str(provider?['bio']);
  int? get yearsExperience => _int(provider?['years_experience']);
  double? get rating => _double(provider?['rating']);
  int? get totalReviews => _int(provider?['total_reviews']);
  List<String> get languages => _strings(provider?['languages']);

  static DossierPractice fromJson(Map<String, dynamic> j) => DossierPractice(
        provider: j['provider'] is Map ? _map(j['provider']) : null,
        caseloadActive: _int(j['caseload_active']) ?? 0,
        caseloadEnded: _int(j['caseload_ended']) ?? 0,
        caseload: _listOf(j['caseload']),
        careRequestsHandled: _int(j['care_requests_handled']) ?? 0,
        careRequestsPending: _int(j['care_requests_pending']) ?? 0,
        prescriptionsIssued: _int(j['prescriptions_issued']) ?? 0,
        prescriptionsActive: _int(j['prescriptions_active']) ?? 0,
        reportsAuthored: _int(j['reports_authored']) ?? 0,
        reportsPublished: _int(j['reports_published']) ?? 0,
        mealPlansAssigned: _int(j['meal_plans_assigned']) ?? 0,
        appointmentsTotal: _int(j['appointments_total']) ?? 0,
        appointmentsUpcoming: _int(j['appointments_upcoming']) ?? 0,
        recentAppointments: _listOf(j['recent_appointments']),
        recentReports: _listOf(j['recent_reports']),
        patientsAlerting: _int(j['patients_alerting']) ?? 0,
      );
}

class DossierAccess {
  const DossierAccess({
    this.implicitAll = false,
    this.granted = const [],
    this.available = const [],
    this.grants = const [],
    this.supportTicketsAssigned = 0,
  });

  /// Admins hold every permission implicitly rather than by explicit grant.
  final bool implicitAll;
  final List<String> granted;
  final List<String> available;
  final List<Map<String, dynamic>> grants;
  final int supportTicketsAssigned;

  static DossierAccess fromJson(Map<String, dynamic> j) => DossierAccess(
        implicitAll: j['implicit_all'] == true,
        granted: _strings(j['granted']),
        available: _strings(j['available']),
        grants: _listOf(j['grants']),
        supportTicketsAssigned: _int(j['support_tickets_assigned']) ?? 0,
      );
}

// ---------------------------------------------------------------------------
// parsing helpers
// ---------------------------------------------------------------------------

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _listOf(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : const [];

List<String> _strings(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : const [];

String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

int? _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _date(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

UserRole _role(dynamic v) {
  final raw = '$v';
  return switch (raw) {
    'patient' => UserRole.patient,
    'doctor' || 'healthworker' => UserRole.doctor,
    'mcareAssistant' || 'mcare_assistant' => UserRole.mcareAssistant,
    'admin' => UserRole.admin,
    _ => UserRole.patient,
  };
}

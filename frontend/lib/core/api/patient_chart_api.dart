import 'package:intl/intl.dart';

import '../../shared/auth/auth_state.dart';
import '../../shared/models/patient_profile.dart';
import '../../shared/models/sos.dart';
import '../../shared/models/user_role.dart';
import '../../shared/models/vital.dart';
import '../env/app_env.dart';
import '../location/google_maps_service.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';
import 'patient_profile_mapper.dart';

/// How a chart period is anchored.
///
/// A rolling window answers "the last N days" and moves with the clock; a
/// calendar span answers "this month" and stays put; a custom range is two
/// dates a reader chose. They are different questions, and a filter offering
/// only one of them leaves the other to be counted out by hand.
enum ChartPeriodKind { rolling, calendar, custom }

/// The window a chart is read over — and the only place a period is defined.
///
/// A chart with no period is a chart that answers "ever", which is the one
/// question a clinician is never asking. Every screen that filters by time —
/// the chart a doctor opens, the same chart an admin opens — takes its presets
/// from here, so "Last 30 days" is the same 30 days everywhere and a reader
/// moving between roles never has to re-learn the control.
class ChartPeriod {
  const ChartPeriod._(
    this.kind,
    this.label,
    this.shortLabel, {
    this.from,
    this.to,
    this.presetKey,
  }) : days = null;

  /// A rolling window of [days] ending now.
  const ChartPeriod.days(int this.days, this.label, this.shortLabel)
    : kind = ChartPeriodKind.rolling,
      from = null,
      to = null,
      presetKey = null;

  /// Two dates a reader picked. Snapped to whole days so the window shown is
  /// the window the server reads, and ordered so a backwards pick still works.
  factory ChartPeriod.range(DateTime from, DateTime to, [String? label]) {
    var start = _dayStart(from);
    var end = _dayEnd(to);
    if (start.isAfter(end)) {
      final swap = start;
      start = _dayStart(end);
      end = _dayEnd(swap);
    }
    return ChartPeriod._(
      ChartPeriodKind.custom,
      label ?? rangeLabel(start, end),
      shortRangeLabel(start, end),
      from: start,
      to: end,
    );
  }

  /// A named calendar span — this month, last month, year to date.
  factory ChartPeriod.calendar({
    required String key,
    required String label,
    required String shortLabel,
    required DateTime from,
    required DateTime to,
  }) => ChartPeriod._(
    ChartPeriodKind.calendar,
    label,
    shortLabel,
    from: _dayStart(from),
    to: _dayEnd(to),
    presetKey: key,
  );

  final ChartPeriodKind kind;
  final String label;

  /// What a one-line bar shows when there is no room for the full label.
  final String shortLabel;
  final int? days;
  final DateTime? from;
  final DateTime? to;

  /// Identity of a calendar preset, so a picker can tell which one is showing.
  final String? presetKey;

  /// Longest window the chart endpoint assembles in one read. Mirrors
  /// PatientChartController::MAX_DAYS — a picker that offers more than the
  /// server will read is a picker that silently answers a different question.
  static const int maxDays = 366;

  static const week = ChartPeriod.days(7, 'Last 7 days', '7d');
  static const threeWeeks = ChartPeriod.days(21, 'Last 3 weeks', '3w');
  static const month = ChartPeriod.days(30, 'Last 30 days', '30d');
  static const quarter = ChartPeriod.days(90, 'Last 90 days', '90d');
  static const halfYear = ChartPeriod.days(180, 'Last 6 months', '6m');
  static const year = ChartPeriod.days(365, 'Last 12 months', '12m');

  static const presets = [week, threeWeeks, month, quarter, halfYear, year];

  /// Calendar spans resolved against [now], so "this month" is this month.
  static List<ChartPeriod> calendarPresets([DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final monthStart = DateTime(n.year, n.month, 1);
    final lastMonthStart = DateTime(n.year, n.month - 1, 1);
    // Day zero of this month is the last day of the previous one.
    final lastMonthEnd = DateTime(n.year, n.month, 0);

    return [
      ChartPeriod.calendar(
        key: 'today',
        label: 'Today',
        shortLabel: 'Today',
        from: today,
        to: today,
      ),
      ChartPeriod.calendar(
        key: 'yesterday',
        label: 'Yesterday',
        shortLabel: 'Yest.',
        from: yesterday,
        to: yesterday,
      ),
      ChartPeriod.calendar(
        key: 'this-week',
        label: 'This week',
        shortLabel: 'Week',
        from: today.subtract(Duration(days: today.weekday - 1)),
        to: today,
      ),
      ChartPeriod.calendar(
        key: 'this-month',
        label: 'This month',
        shortLabel: DateFormat.MMM().format(monthStart),
        from: monthStart,
        to: today,
      ),
      ChartPeriod.calendar(
        key: 'last-month',
        label: 'Last month',
        shortLabel: DateFormat.MMM().format(lastMonthStart),
        from: lastMonthStart,
        to: lastMonthEnd,
      ),
      ChartPeriod.calendar(
        key: 'ytd',
        label: 'Year to date',
        shortLabel: 'YTD',
        from: DateTime(n.year, 1, 1),
        to: today,
      ),
    ];
  }

  bool get isCustom => kind == ChartPeriodKind.custom;

  /// Whether this period already carries the two dates it means.
  bool get hasRange => from != null && to != null;

  /// Stable identity for selection state in a picker.
  String get key => switch (kind) {
    ChartPeriodKind.rolling => 'rolling:${days ?? 30}',
    ChartPeriodKind.calendar => 'calendar:$presetKey',
    ChartPeriodKind.custom => 'custom',
  };

  /// The concrete window, so a bar can print the dates before the chart that
  /// confirms them has finished loading.
  ({DateTime from, DateTime to}) resolve([DateTime? now]) {
    if (hasRange) return (from: from!, to: to!);
    final end = _dayEnd(now ?? DateTime.now());
    return (from: end.subtract(Duration(days: days ?? 30)), to: end);
  }

  /// How many days the window covers, counted the way a reader counts them.
  int spanDays([DateTime? now]) {
    final window = resolve(now);
    final span = window.to.difference(window.from).inDays;
    return hasRange ? span + 1 : span;
  }

  /// 'Jul 29 – Aug 28, 2026' — one phrasing wherever a window is printed.
  String get rangeText {
    final window = resolve();
    return rangeLabel(window.from, window.to);
  }

  String get query {
    if (hasRange) {
      final fmt = DateFormat('yyyy-MM-dd');
      return '?from=${fmt.format(from!)}&to=${fmt.format(to!)}';
    }
    return '?days=${days ?? 30}';
  }

  static String rangeLabel(DateTime from, DateTime to) {
    if (_sameDay(from, to)) return DateFormat.yMMMd().format(from);
    final start = from.year == to.year
        ? DateFormat.MMMd().format(from)
        : DateFormat.yMMMd().format(from);
    return '$start – ${DateFormat.yMMMd().format(to)}';
  }

  static String shortRangeLabel(DateTime from, DateTime to) =>
      _sameDay(from, to)
      ? DateFormat.MMMd().format(from)
      : '${DateFormat.MMMd().format(from)} – ${DateFormat.MMMd().format(to)}';

  @override
  bool operator ==(Object other) =>
      other is ChartPeriod &&
      other.key == key &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(key, from, to);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime _dayStart(DateTime t) => DateTime(t.year, t.month, t.day);

  static DateTime _dayEnd(DateTime t) =>
      DateTime(t.year, t.month, t.day, 23, 59, 59);
}

/// One vital's shape over the window — the line, where it ended, and how much
/// of the period sat in range.
class ChartVital {
  const ChartVital({
    required this.key,
    required this.count,
    required this.points,
    required this.trend,
    this.inRangePct,
    this.latestValue,
    this.latestRisk,
    this.latestAt,
  });

  final VitalKey key;
  final int count;
  final List<ChartPoint> points;

  /// 'up' | 'down' | 'flat'. Flat below four readings — fewer than that is
  /// not a trend, and drawing one would be the chart inventing a finding.
  final String trend;
  final int? inRangePct;
  final String? latestValue;
  final RiskLevel? latestRisk;
  final DateTime? latestAt;

  static ChartVital fromApi(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?)?.cast<String, dynamic>();
    return ChartVital(
      key: PatientProfileMapper.vitalKeyFromApi(
        (json['key'] ?? 'heartRate').toString(),
      ),
      count: (json['count'] as num?)?.toInt() ?? 0,
      inRangePct: (json['in_range_pct'] as num?)?.toInt(),
      trend: (json['trend'] ?? 'flat').toString(),
      latestValue: latest?['display_value']?.toString(),
      latestRisk: latest == null
          ? null
          : PatientDomainMapper.riskFromApi(latest['risk'] as String?),
      latestAt: _date(latest?['recorded_at']),
      points: ((json['points'] as List?) ?? const [])
          .map((e) => ChartPoint.fromApi((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class ChartPoint {
  const ChartPoint({required this.value, required this.risk, this.at});

  final double value;
  final RiskLevel risk;
  final DateTime? at;

  static ChartPoint fromApi(Map<String, dynamic> json) => ChartPoint(
    value: (json['value'] as num?)?.toDouble() ?? 0,
    risk: PatientDomainMapper.riskFromApi(json['risk'] as String?),
    at: _date(json['at']),
  );
}

/// A row on one of the chart's list sections. Deliberately one shape for
/// medications, meals, appointments, alerts, SOS and documents: the chart
/// renders them identically, and six near-identical model classes would only
/// be six places for the same field to be spelled differently.
class ChartEntry {
  const ChartEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.at,
    this.trailing,
    this.tone,
    this.detail,
  });

  final String id;
  final String title;
  final String subtitle;
  final DateTime? at;

  /// Short status word — 'Active', 'Completed', 'Critical'.
  final String? trailing;

  /// 'critical' | 'warning' | 'success' | null — how the row should read.
  final String? tone;
  final String? detail;
}

/// Someone currently responsible for this patient.
class ChartCareTeamMember {
  const ChartCareTeamMember({
    required this.name,
    required this.role,
    this.specialty,
    this.assignedAt,
    this.assignedBy,
  });

  final String name;
  final String role;
  final String? specialty;
  final DateTime? assignedAt;
  final String? assignedBy;

  static ChartCareTeamMember fromApi(Map<String, dynamic> json) =>
      ChartCareTeamMember(
        name: (json['provider_name'] ?? 'Provider').toString(),
        role: (json['role'] ?? 'Care provider').toString(),
        specialty: json['provider_specialty'] as String?,
        assignedAt: _date(json['assigned_at']),
        assignedBy: json['assigned_by_name'] as String?,
      );
}

/// Where the patient was last known to be.
class ChartLocation {
  const ChartLocation({
    this.address,
    this.lastSeenLabel,
    this.latitude,
    this.longitude,
    this.at,
    required this.source,
    required this.consent,
  });

  final String? address;
  final String? lastSeenLabel;
  final double? latitude;
  final double? longitude;
  final DateTime? at;

  /// 'sos' when the fix came from an emergency, 'profile' otherwise.
  final String source;
  final bool consent;

  bool get hasFix => latitude != null && longitude != null;

  String? get mapsUrl => hasFix
      ? GoogleMapsService.searchUri(latitude!, longitude!).toString()
      : null;

  String? get directionsUrl => hasFix
      ? GoogleMapsService.directionsUri(latitude!, longitude!).toString()
      : null;

  static ChartLocation fromApi(Map<String, dynamic> json) => ChartLocation(
    address: json['address'] as String?,
    lastSeenLabel: json['last_seen_label'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
    at: _date(json['at']),
    source: (json['source'] ?? 'profile').toString(),
    consent: json['consent'] == true,
  );
}

/// The counted facts of the window, above the sections that detail them.
class ChartSummary {
  const ChartSummary(this._raw);
  final Map<String, dynamic> _raw;

  int count(String key) => (_raw[key] as num?)?.toInt() ?? 0;
  int? pct(String key) => (_raw[key] as num?)?.toInt();

  int get readings => count('readings');

  /// How much of what was measured sat in range. Null when nothing was
  /// measured — an unmonitored patient is not a healthy one.
  int? get inRangePct => pct('in_range_pct');
  int? get adherencePct => pct('adherence_pct');
  int get alerts => count('alerts');
  int get alertsCritical => count('alerts_critical');
  int get sos => count('sos');
  int get sosOpen => count('sos_open');
  int get appointments => count('appointments');
  int get appointmentsKept => count('appointments_kept');
  int get appointmentsMissed => count('appointments_missed');
  int get medicationsActive => count('medications_active');
  int get dosesTaken => count('doses_taken');
  int get dosesScheduled => count('doses_scheduled');
  int get meals => count('meals');
  int get documents => count('documents');
  int get notes => count('notes');
}

/// One patient's clinical record over a chosen period.
class PatientChart {
  const PatientChart({
    required this.patientId,
    required this.name,
    required this.from,
    required this.to,
    required this.summary,
    required this.location,
    required this.nextOfKin,
    required this.careTeam,
    required this.vitals,
    required this.alerts,
    required this.sos,
    required this.medications,
    required this.meals,
    required this.appointments,
    required this.documents,
    required this.notes,
    this.uniqueId,
    this.email,
    this.phone,
    this.status,
    this.joinedAt,
    this.health,
  });

  final String patientId;
  final String name;
  final String? uniqueId;
  final String? email;
  final String? phone;
  final String? status;
  final DateTime? joinedAt;
  final DateTime from;
  final DateTime to;
  final PatientHealthProfile? health;
  final ChartSummary summary;
  final ChartLocation location;
  final List<EmergencyContact> nextOfKin;
  final List<ChartCareTeamMember> careTeam;
  final List<ChartVital> vitals;
  final List<ChartEntry> alerts;
  final List<ChartEntry> sos;
  final List<ChartEntry> medications;
  final List<ChartEntry> meals;
  final List<ChartEntry> appointments;
  final List<ChartEntry> documents;
  final List<ChartEntry> notes;

  PatientChart withNote(ChartEntry note) => PatientChart(
    patientId: patientId,
    name: name,
    uniqueId: uniqueId,
    email: email,
    phone: phone,
    status: status,
    joinedAt: joinedAt,
    from: from,
    to: to,
    health: health,
    summary: summary,
    location: location,
    nextOfKin: nextOfKin,
    careTeam: careTeam,
    vitals: vitals,
    alerts: alerts,
    sos: sos,
    medications: medications,
    meals: meals,
    appointments: appointments,
    documents: documents,
    notes: [note, ...notes],
  );
}

/// Reads the clinical chart and writes notes back onto it.
///
/// The path differs by role — a doctor is held to their own caseload under
/// `/doctor`, a coordinator works platform-wide under `/admin` — but the
/// payload is identical, so nothing above this branches on it.
class PatientChartApi {
  PatientChartApi._();
  static final PatientChartApi instance = PatientChartApi._();

  String _base(String patientId) {
    final role = AuthState.instance.user?.role;
    return role == UserRole.doctor
        ? '/doctor/patients/$patientId'
        : '/admin/patients/$patientId';
  }

  Future<PatientChart?> fetch(String patientId, ChartPeriod period) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.get(
      '${_base(patientId)}/chart${period.query}',
    );
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    return data == null ? null : _parse(patientId, data);
  }

  /// Writes a note against the chart. `publish` shares it with the patient
  /// and makes it eligible for the notes section of an issued report.
  Future<ChartEntry?> addNote(
    String patientId, {
    required String title,
    required String body,
    bool publish = false,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '${_base(patientId)}/notes',
      body: {'title': title, 'body': body, 'publish': publish},
    );
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    final json = (data?['note'] as Map?)?.cast<String, dynamic>();
    return json == null ? null : _note(json);
  }

  PatientChart _parse(String patientId, Map<String, dynamic> data) {
    final patient = (data['patient'] as Map?)?.cast<String, dynamic>() ?? {};
    final window = (data['window'] as Map?)?.cast<String, dynamic>() ?? {};

    List<Map<String, dynamic>> list(String key) =>
        ((data[key] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();

    return PatientChart(
      patientId: patientId,
      name: (patient['name'] ?? 'Patient').toString(),
      uniqueId: patient['unique_id'] as String?,
      email: patient['email'] as String?,
      phone: patient['phone'] as String?,
      status: patient['status'] as String?,
      joinedAt: _date(patient['joined_at']),
      from: _date(window['from']) ?? DateTime.now(),
      to: _date(window['to']) ?? DateTime.now(),
      health: _health(data['health']),
      summary: ChartSummary(
        (data['summary'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      location: ChartLocation.fromApi(
        (data['location'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      nextOfKin: list('next_of_kin').map(_contact).toList(),
      careTeam: list('care_team').map(ChartCareTeamMember.fromApi).toList(),
      vitals: list('vitals').map(ChartVital.fromApi).toList(),
      alerts: list('alerts').map(_alert).toList(),
      sos: list('sos').map(_sos).toList(),
      medications: list('medications').map(_medication).toList(),
      meals: list('meals').map(_meal).toList(),
      appointments: list('appointments').map(_appointment).toList(),
      documents: list('documents').map(_document).toList(),
      notes: list('notes').map(_note).toList(),
    );
  }

  PatientHealthProfile? _health(Object? raw) {
    if (raw is! Map) return null;
    try {
      return PatientProfileMapper.healthFromApi(raw.cast<String, dynamic>());
    } catch (_) {
      // A half-filled profile is not a reason to lose the whole chart.
      return null;
    }
  }

  EmergencyContact _contact(Map<String, dynamic> json) => EmergencyContact(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    relationship: (json['relationship'] ?? '').toString(),
    phone: (json['phone'] ?? '').toString(),
    email: json['email'] as String?,
    priority: (json['priority'] as num?)?.toInt() ?? 1,
  );

  ChartEntry _alert(Map<String, dynamic> json) {
    final critical = json['kind'] == 'vital_critical' || json['kind'] == 'sos';
    return ChartEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Alert').toString(),
      subtitle: (json['body'] ?? '').toString(),
      at: _date(json['created_at']),
      trailing: json['resolved'] == true ? 'Resolved' : 'Open',
      tone: json['resolved'] == true
          ? 'success'
          : (critical ? 'critical' : 'warning'),
    );
  }

  ChartEntry _sos(Map<String, dynamic> json) => ChartEntry(
    id: (json['id'] ?? '').toString(),
    title: _kindLabel((json['kind'] ?? '').toString()),
    subtitle: [
      json['location_label'],
      json['note'],
      json['resolution_label'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · '),
    at: _date(json['triggered_at']),
    trailing: _sosStatus((json['status'] ?? '').toString()),
    tone: const ['active', 'acknowledged'].contains(json['status'])
        ? 'critical'
        : 'success',
    detail: json['responded_by'] as String?,
  );

  ChartEntry _medication(Map<String, dynamic> json) {
    final active = json['active'] == true;
    return ChartEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['name'] ?? 'Medication').toString(),
      subtitle: [
        json['dosage'],
        json['frequency'],
        json['form'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · '),
      at: _date(json['start_date']),
      trailing: active ? 'Active' : 'Stopped',
      tone: active ? 'success' : null,
      detail: [
        if (json['instructions'] != null) json['instructions'] as String,
        if (json['prescribed_by_name'] != null)
          'Prescribed by ${json['prescribed_by_name']}',
      ].join(' — '),
    );
  }

  ChartEntry _meal(Map<String, dynamic> json) => ChartEntry(
    id: (json['id'] ?? '').toString(),
    title: (json['title'] ?? 'Meal plan').toString(),
    subtitle: [
      json['meal_type'],
      if (json['calories'] != null) '${json['calories']} kcal',
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · '),
    at: _date(json['assigned_at']),
    detail: json['notes'] as String? ?? json['description'] as String?,
  );

  ChartEntry _appointment(Map<String, dynamic> json) {
    final status = (json['status'] ?? '').toString();
    return ChartEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['doctor_name'] ?? 'Appointment').toString(),
      subtitle: [
        json['type'],
        json['reason'],
        json['location_or_link'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · '),
      at: _date(json['scheduled_at']),
      trailing: status.isEmpty ? null : _titleCase(status),
      tone: switch (status) {
        'completed' => 'success',
        'missed' || 'cancelled' => 'warning',
        _ => null,
      },
    );
  }

  ChartEntry _document(Map<String, dynamic> json) => ChartEntry(
    id: (json['id'] ?? '').toString(),
    title: (json['title'] ?? 'Document').toString(),
    subtitle: _titleCase((json['category'] ?? '').toString()),
    at: _date(json['uploaded_at']),
  );

  ChartEntry _note(Map<String, dynamic> json) => ChartEntry(
    id: (json['id'] ?? '').toString(),
    title: (json['title'] ?? 'Note').toString(),
    subtitle: (json['author_name'] ?? '').toString(),
    at: _date(json['created_at']),
    trailing: json['published'] == true ? 'Shared' : 'Draft',
    tone: json['published'] == true ? 'success' : null,
    detail: json['body'] as String?,
  );

  String _kindLabel(String kind) => switch (kind) {
    'medical' => 'Medical emergency',
    'accident' => 'Accident',
    'fall' => 'Fall',
    'panic' => 'Panic',
    _ => 'Emergency',
  };

  String _sosStatus(String status) => switch (status) {
    'active' => 'Active',
    'acknowledged' => 'Owned',
    'falseAlarm' => 'False alarm',
    'resolved' => 'Resolved',
    _ => status,
  };

  String _titleCase(String raw) {
    if (raw.isEmpty) return raw;
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

DateTime? _date(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

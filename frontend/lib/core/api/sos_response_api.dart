import '../env/app_env.dart';
import '../../shared/auth/auth_state.dart';
import '../../shared/models/user_role.dart';
import 'api_client.dart';

/// One recorded step in how an emergency was worked.
class SosResponseStep {
  const SosResponseStep({
    required this.id,
    required this.action,
    required this.label,
    required this.actorName,
    required this.createdAt,
    this.detail,
  });

  final String id;
  final String action;
  final String label;
  final String actorName;
  final DateTime createdAt;
  final String? detail;

  static SosResponseStep fromApi(Map<String, dynamic> json) {
    return SosResponseStep(
      id: (json['id'] ?? '').toString(),
      action: (json['action'] ?? '').toString(),
      label: (json['label'] ?? 'Step').toString(),
      actorName: (json['actor_name'] ?? '').toString(),
      detail: json['detail'] as String?,
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// The steps a responder can record. Mirrors `SosResponseAction::ACTIONS`;
/// the server rejects anything else, so the two lists must not drift.
class SosResponseActions {
  SosResponseActions._();

  static const openedResponse = 'opened_response';
  static const calledPatient = 'called_patient';
  static const viewedLocation = 'viewed_location';
  static const openedChart = 'opened_chart';
  static const assignedProvider = 'assigned_provider';
  static const tookOwnership = 'took_ownership';
  static const note = 'note';
}

/// One provider who could take a handover.
class SosCandidate {
  const SosCandidate({
    required this.providerId,
    required this.name,
    required this.onCareTeam,
    required this.available,
    this.userId,
    this.specialty,
    this.facility,
  });

  final String providerId;
  final String? userId;
  final String name;
  final String? specialty;
  final String? facility;

  /// Already on this patient's care team — the first place a handover should
  /// go, because they know the history.
  final bool onCareTeam;
  final bool available;

  static SosCandidate fromApi(Map<String, dynamic> json) => SosCandidate(
    providerId: (json['provider_id'] ?? '').toString(),
    userId: json['user_id']?.toString(),
    name: (json['name'] ?? 'Provider').toString(),
    specialty: json['specialty'] as String?,
    facility: json['facility'] as String?,
    onCareTeam: json['on_care_team'] == true,
    available: json['available'] == true,
  );
}

/// Reads and appends the response trail for an SOS event.
///
/// The path differs by role — admins and assistants coordinate platform-wide
/// under `/admin`, a doctor works their own caseload under `/doctor` — but
/// the payload is identical, so callers never branch on it.
class SosResponseApi {
  SosResponseApi._();
  static final SosResponseApi instance = SosResponseApi._();

  String _base(String eventId) {
    final role = AuthState.instance.user?.role;
    return role == UserRole.doctor
        ? '/doctor/sos/$eventId/actions'
        : '/admin/sos-events/$eventId/actions';
  }

  Future<List<SosResponseStep>> list(String eventId) async {
    if (!AppEnv.backendEnabled) return const [];
    final res = await ApiClient.instance.get(_base(eventId));
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    final raw = (data?['actions'] as List?) ?? const [];
    return raw
        .map((e) => SosResponseStep.fromApi((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Who could take this emergency, care team first.
  Future<({List<SosCandidate> careTeam, List<SosCandidate> others})> candidates(
    String eventId,
  ) async {
    if (!AppEnv.backendEnabled) {
      return (careTeam: <SosCandidate>[], others: <SosCandidate>[]);
    }
    final res = await ApiClient.instance.get(
      '/admin/sos-events/$eventId/candidates',
    );
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    List<SosCandidate> parse(String key) => ((data?[key] as List?) ?? const [])
        .map((e) => SosCandidate.fromApi((e as Map).cast<String, dynamic>()))
        .toList();
    return (careTeam: parse('care_team'), others: parse('others'));
  }

  /// Hand this emergency to a provider.
  ///
  /// One call, not two: the server binds the provider to the patient (reusing
  /// the binding when they are already on the care team, which is why the
  /// care team can be chosen at all), stamps the emergency as theirs, writes
  /// the trail step, and notifies them in-app, by push and over the real-time
  /// channel. Returns the recorded step so the trail updates without a reload.
  ///
  /// Throws [ApiException] — the responder is told what actually went wrong.
  Future<SosResponseStep?> handover(
    String eventId, {
    required String providerId,
    String? detail,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/admin/sos-events/$eventId/handover',
      body: {
        'provider_id': providerId,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
      },
    );
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    final json = (data?['action'] as Map?)?.cast<String, dynamic>();
    return json == null ? null : SosResponseStep.fromApi(json);
  }

  /// Appends one step. Returns null when the write did not land, so callers
  /// can say so rather than showing a trail entry the server never took.
  Future<SosResponseStep?> record(
    String eventId, {
    required String action,
    String? detail,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      _base(eventId),
      body: {'action': action, if (detail != null) 'detail': detail},
    );
    final data = (res['data'] as Map?)?.cast<String, dynamic>();
    final json = (data?['action'] as Map?)?.cast<String, dynamic>();
    return json == null ? null : SosResponseStep.fromApi(json);
  }
}

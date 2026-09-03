import '../env/app_env.dart';
import 'api_client.dart';

/// The signed-in patient's own record — the same dossier staff read about
/// them, served by `/patient/record`.
///
/// It deliberately mirrors `AdminApi.userDossier` rather than inventing a
/// patient-shaped payload, so one set of dossier widgets renders both and the
/// patient can never be shown a quietly different version of their record.
class PatientRecordApi {
  PatientRecordApi._();

  static final PatientRecordApi instance = PatientRecordApi._();

  /// Raw dossier envelope, parsed by `UserDossier.fromJson`.
  ///
  /// Returns null when the backend is switched off (demo/mock builds), which
  /// callers surface as "this needs the backend" rather than an error.
  Future<Map<String, dynamic>?> fetch() async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.get('/patient/record');
    return (res['data'] as Map?)?.cast<String, dynamic>();
  }

  /// Ask the care team for a complete report of the record, stating why.
  ///
  /// The reason becomes the request's purpose, so the doctor asked to sign it
  /// knows what it is for. Throws on refusal — no care-team doctor to sign, or
  /// a request already in flight — with the server's message.
  Future<Map<String, dynamic>> requestFullReport({
    required String reason,
    String? recipient,
  }) async {
    if (!AppEnv.backendEnabled) {
      throw UnsupportedError('Report requests need the backend connection.');
    }
    final res = await ApiClient.instance.post(
      '/patient/record/report-requests',
      body: {
        'reason': reason.trim(),
        if (recipient != null && recipient.trim().isNotEmpty)
          'recipient': recipient.trim(),
      },
    );
    return (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }
}

/// Whether the patient may raise a report right now, and who would sign it.
///
/// Decided by the server and carried on the dossier so the button and the
/// endpoint can never disagree about what is allowed.
class PatientReportAccess {
  const PatientReportAccess({
    required this.canRequest,
    required this.hasCareTeam,
    required this.openRequests,
    this.signerName,
    this.sections = const [],
  });

  final bool canRequest;
  final bool hasCareTeam;
  final int openRequests;
  final String? signerName;

  /// Every section a full report covers, as `(label, description)` pairs —
  /// shown before asking so the patient knows what they are requesting.
  final List<({String label, String description})> sections;

  static const empty = PatientReportAccess(
    canRequest: false,
    hasCareTeam: false,
    openRequests: 0,
  );

  /// Why the request button is disabled, or null when it is not.
  String? get blockedReason {
    if (canRequest) return null;
    if (!hasCareTeam) {
      return 'A doctor has to sign a report before it can be issued, and you '
          'do not have one assigned yet. Ask for a provider from your care '
          'team first.';
    }
    if (openRequests > 0) {
      return 'You already have a report request in progress. Your care team '
          'will let you know as soon as it is ready.';
    }
    return 'Report requests are not available right now.';
  }

  static PatientReportAccess fromJson(Map<String, dynamic>? json) {
    if (json == null) return empty;
    final rawSections = json['sections'];
    return PatientReportAccess(
      canRequest: json['can_request'] == true,
      hasCareTeam: json['has_care_team'] == true,
      openRequests: (json['open_requests'] as num?)?.toInt() ?? 0,
      signerName: (json['signer_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['signer_name'] as String,
      sections: rawSections is List
          ? rawSections
                .whereType<Map>()
                .map(
                  (s) => (
                    label: '${s['label'] ?? ''}',
                    description: '${s['description'] ?? ''}',
                  ),
                )
                .where((s) => s.label.isNotEmpty)
                .toList()
          : const [],
    );
  }
}

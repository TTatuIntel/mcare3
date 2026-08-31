import 'package:flutter/foundation.dart';

import '../../core/api/report_consents_api.dart';
import '../../core/env/app_env.dart';
import '../models/patient_report_request.dart';

/// Requests to disclose part of the patient's record, and which of them are
/// still waiting on the patient.
///
/// This exists because a consent request used to reach the patient through a
/// single notification and nothing else. Once that notification was read,
/// dismissed or simply scrolled past there was no route back to the approval
/// screen, and the request sat on "Awaiting patient consent" until it expired.
/// Holding the requests in a store instead means the session poller keeps them
/// current, and the home prompt, the More badge and the approval screen all
/// read the same outstanding count.
class ReportConsentsState extends ChangeNotifier {
  ReportConsentsState._();
  static final ReportConsentsState instance = ReportConsentsState._();

  final List<PatientReportRequestItem> _requests = [];

  List<PatientReportRequestItem> get requests => List.unmodifiable(_requests);

  /// Requests the patient still has to approve or decline, newest first.
  List<PatientReportRequestItem> get awaiting =>
      _requests.where((r) => r.awaitingMe).toList(growable: false);

  int get awaitingCount => _requests.where((r) => r.awaitingMe).length;

  bool get hasAwaiting => awaitingCount > 0;

  void seed(List<PatientReportRequestItem> initial) {
    if (!_differs(initial)) return;
    _requests
      ..clear()
      ..addAll(initial);
    notifyListeners();
  }

  /// The session poller reseeds on every tick, so only a real change should
  /// wake the nav badges and the home prompt.
  bool _differs(List<PatientReportRequestItem> next) {
    if (next.length != _requests.length) return true;
    for (var i = 0; i < next.length; i++) {
      final a = _requests[i];
      final b = next[i];
      if (a.id != b.id ||
          a.status != b.status ||
          a.awaitingMe != b.awaitingMe ||
          a.consentExpiresAt != b.consentExpiresAt) {
        return true;
      }
    }
    return false;
  }

  /// Pulls the patient's own consent list. Safe to call when the backend is
  /// off — the store simply stays empty.
  Future<void> refresh() async {
    if (!AppEnv.backendEnabled) return;
    final rows = await ReportConsentsApi.instance.list();
    seed(rows.map(PatientReportRequestItem.fromJson).toList());
  }

  /// Replaces one request after the patient approves or declines it, so the
  /// badge clears without waiting for the next poll.
  void replace(PatientReportRequestItem updated) {
    final i = _requests.indexWhere((r) => r.id == updated.id);
    if (i == -1) return;
    _requests[i] = updated;
    notifyListeners();
  }
}

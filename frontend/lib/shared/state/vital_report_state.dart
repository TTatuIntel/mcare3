import 'package:flutter/foundation.dart';

import '../../core/api/vital_reports_api.dart';
import '../../core/env/app_env.dart';
import '../models/user_role.dart';
import '../models/vital.dart';
import '../models/vital_report_request.dart';

/// Patient vital report requests with doctor → assistant → admin escalation.
class VitalReportState extends ChangeNotifier {
  VitalReportState._();
  static final VitalReportState instance = VitalReportState._();

  static const _doctorSla = Duration(hours: 48);
  static const _assistantSla = Duration(hours: 24);

  final List<VitalReportRequest> _requests = [];

  List<VitalReportRequest> get requests => List.unmodifiable(_requests);
  List<VitalReportRequest> get pending =>
      _requests.where((r) => r.isPending).toList(growable: false);
  List<VitalReportRequest> get fulfilled =>
      _requests.where((r) => r.status == VitalReportStatus.fulfilled).toList(growable: false);

  void seed(List<VitalReportRequest> initial) {
    _requests
      ..clear()
      ..addAll(initial);
    notifyListeners();
  }

  VitalReportRequest requestReport({
    required DateTime from,
    required DateTime to,
    required List<VitalKey> vitals,
    String? note,
  }) {
    checkEscalations();
    final req = VitalReportRequest(
      id: 'vr_${DateTime.now().millisecondsSinceEpoch}',
      from: from,
      to: to,
      vitals: List.unmodifiable(vitals),
      createdAt: DateTime.now(),
      status: VitalReportStatus.pending,
      currentResponder: UserRole.doctor,
      note: note,
    );
    _requests.insert(0, req);
    notifyListeners();
    return req;
  }

  /// Advances pending requests when SLA windows expire without a response.
  void checkEscalations() {
    final now = DateTime.now();
    var changed = false;

    for (var i = 0; i < _requests.length; i++) {
      final r = _requests[i];
      if (!r.isPending) continue;

      final anchor = r.lastEscalatedAt ?? r.createdAt;
      final elapsed = now.difference(anchor);

      if (r.currentResponder == UserRole.doctor &&
          elapsed >= _doctorSla) {
        _requests[i] = r.copyWith(
          currentResponder: UserRole.mcareAssistant,
          lastEscalatedAt: now,
        );
        changed = true;
        continue;
      }

      if (r.currentResponder == UserRole.mcareAssistant &&
          elapsed >= _assistantSla) {
        _requests[i] = r.copyWith(
          currentResponder: UserRole.admin,
          lastEscalatedAt: now,
        );
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  bool respond({
    required String id,
    required UserRole role,
    required String responderName,
    String? note,
  }) {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i == -1) return false;
    final r = _requests[i];
    if (!r.isPending || r.currentResponder != role) return false;

    _requests[i] = r.copyWith(
      status: VitalReportStatus.fulfilled,
      respondedAt: DateTime.now(),
      respondedBy: responderName,
      responseNote: note,
    );
    notifyListeners();
    return true;
  }

  void cancel(String id) {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i == -1 || !_requests[i].isPending) return;
    _requests[i] = _requests[i].copyWith(status: VitalReportStatus.cancelled);
    notifyListeners();
  }

  /// Persisting variant of [requestReport].
  Future<VitalReportRequest> requestReportRemote({
    required DateTime from,
    required DateTime to,
    required List<VitalKey> vitals,
    String? note,
  }) async {
    if (!AppEnv.backendEnabled) {
      return requestReport(from: from, to: to, vitals: vitals, note: note);
    }
    final saved = await VitalReportsApi.instance.submit(
      from: from,
      to: to,
      vitals: vitals,
      note: note,
    );
    if (saved == null) {
      return requestReport(from: from, to: to, vitals: vitals, note: note);
    }
    _requests.insert(0, saved);
    notifyListeners();
    return saved;
  }

  /// Persisting variant of [cancel].
  Future<void> cancelRemote(String id) async {
    final i = _requests.indexWhere((r) => r.id == id);
    if (i == -1 || !_requests[i].isPending) return;
    final original = _requests[i];
    cancel(id);
    if (!AppEnv.backendEnabled) return;
    try {
      final saved = await VitalReportsApi.instance.cancel(id);
      if (saved != null) {
        final j = _requests.indexWhere((r) => r.id == id);
        if (j >= 0) _requests[j] = saved;
        notifyListeners();
      }
    } catch (e) {
      _requests[i] = original;
      notifyListeners();
      rethrow;
    }
  }
}

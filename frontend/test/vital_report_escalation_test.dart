import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/models/vital_report_request.dart';
import 'package:mcare/shared/state/vital_report_state.dart';

VitalReportRequest _req({
  required UserRole responder,
  required Duration age,
  VitalReportStatus status = VitalReportStatus.pending,
  Duration? escalatedAgo,
}) {
  final now = DateTime.now();
  return VitalReportRequest(
    id: 'r_${now.microsecondsSinceEpoch}',
    from: now.subtract(const Duration(days: 7)),
    to: now,
    vitals: const [VitalKey.heartRate],
    createdAt: now.subtract(age),
    status: status,
    currentResponder: responder,
    lastEscalatedAt: escalatedAgo == null ? null : now.subtract(escalatedAgo),
  );
}

void main() {
  final state = VitalReportState.instance;

  test('pending doctor request escalates to assistant after 48h', () {
    state.seed([_req(responder: UserRole.doctor, age: const Duration(hours: 50))]);
    state.checkEscalations();
    expect(state.requests.first.currentResponder, UserRole.mcareAssistant);
  });

  test('pending assistant request escalates to admin after 24h', () {
    state.seed([
      _req(
        responder: UserRole.mcareAssistant,
        age: const Duration(days: 5),
        escalatedAgo: const Duration(hours: 26),
      ),
    ]);
    state.checkEscalations();
    expect(state.requests.first.currentResponder, UserRole.admin);
  });

  test('recent doctor request is not escalated', () {
    state.seed([_req(responder: UserRole.doctor, age: const Duration(hours: 2))]);
    state.checkEscalations();
    expect(state.requests.first.currentResponder, UserRole.doctor);
  });

  test('fulfilled request is never escalated', () {
    state.seed([
      _req(
        responder: UserRole.doctor,
        age: const Duration(days: 10),
        status: VitalReportStatus.fulfilled,
      ),
    ]);
    state.checkEscalations();
    expect(state.requests.first.currentResponder, UserRole.doctor);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/alerts/alert_center.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/staff_state.dart';

/// The escalation engine decides what an admin is interrupted about and when
/// it comes back. A regression here is silent and clinically dangerous, so
/// the ladder, the "returns until attended" promise, and the scope/permission
/// gates are pinned here.
void main() {
  // The engine drives the ring service, which touches haptics and system
  // sound platform channels — those need a binding even in a pure unit test.
  TestWidgetsFlutterBinding.ensureInitialized();

  StaffPatient patient(String id) => StaffPatient(
        id: id,
        name: 'Patient $id',
        age: 40,
        sex: 'F',
        condition: 'Hypertension',
        risk: RiskLevel.normal,
        lastReading: DateTime.now(),
        assignedDoctor: 'Dr. Test',
      );

  StaffAlert alert(
    String id, {
    required String patientId,
    RiskLevel severity = RiskLevel.critical,
    bool acknowledged = false,
    bool resolved = false,
  }) =>
      StaffAlert(
        id: id,
        patientId: patientId,
        patientName: 'Patient $patientId',
        vital: VitalKey.bloodPressure,
        value: '190/120',
        severity: severity,
        createdAt: DateTime.now(),
        acknowledged: acknowledged,
        resolved: resolved,
      );

  void seed(List<StaffPatient> patients, List<StaffAlert> alerts) {
    StaffState.instance.seedFromApi(
      patients: patients,
      alerts: alerts,
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      sosEvents: const [],
    );
  }

  void signInAs(UserRole role) {
    AuthState.instance.signIn(
      AppUser(
        id: 'u1',
        uniqueId: 'MCR-000001',
        firstName: 'Test',
        lastName: 'Staff',
        email: 'staff@mcare.health',
        role: role,
      ),
    );
  }

  setUp(() {
    AlertCenter.instance.reset();
    signInAs(UserRole.admin);
  });

  tearDown(() {
    AlertCenter.instance.reset();
    StaffState.instance.clear();
  });

  test('outstanding alerts are due immediately on app open', () {
    seed([patient('p1')], [alert('a1', patientId: 'p1')]);

    // The old overlay seeded itself and swallowed anything already present,
    // so a cold open showed nothing. Anything unattended must be due at once.
    expect(AlertCenter.instance.dueNow, hasLength(1));
    expect(AlertCenter.instance.unattendedCount, 1);
  });

  test('an item is not due again until its ladder step elapses', () {
    seed([patient('p1')], [alert('a1', patientId: 'p1')]);

    AlertCenter.instance.markSurfaced(['alert:a1']);

    // Shown once — the next rung is minutes away, so not due right now.
    expect(AlertCenter.instance.dueNow, isEmpty);
    expect(AlertCenter.instance.surfaceCountFor('alert:a1'), 1);

    // ...but it is still outstanding, i.e. it will come back.
    expect(AlertCenter.instance.unattendedCount, 1);
  });

  test('snoozing defers without attending', () {
    seed([patient('p1')], [alert('a1', patientId: 'p1')]);

    AlertCenter.instance.snooze('alert:a1', const Duration(minutes: 5));

    expect(AlertCenter.instance.dueNow, isEmpty);
    expect(AlertCenter.instance.unattendedCount, 1,
        reason: 'a snoozed alert is still unattended');

    // A zero snooze is how "review all" forces the queue back up.
    AlertCenter.instance.snooze('alert:a1', Duration.zero);
    expect(AlertCenter.instance.dueNow, hasLength(1));
  });

  test('acknowledging stops the popping but keeps it on the board', () {
    seed([patient('p1')], [alert('a1', patientId: 'p1', acknowledged: true)]);

    expect(AlertCenter.instance.popQueue, isEmpty,
        reason: 'an owned alert must not keep interrupting');
    expect(AlertCenter.instance.openQueue, hasLength(1),
        reason: 'acknowledging is not finishing — it stays visible');
  });

  test('resolving removes it entirely', () {
    seed([patient('p1')], [alert('a1', patientId: 'p1', resolved: true)]);

    expect(AlertCenter.instance.openQueue, isEmpty);
    expect(AlertCenter.instance.dueNow, isEmpty);
  });

  test('critical outranks warning in the queue order', () {
    seed(
      [patient('p1'), patient('p2')],
      [
        alert('warn', patientId: 'p1', severity: RiskLevel.warning),
        alert('crit', patientId: 'p2'),
      ],
    );

    final queue = AlertCenter.instance.openQueue;
    expect(queue.first.id, 'alert:crit');
    expect(queue.first.kind, UrgentKind.criticalVital);
  });

  test('only critical items ring the device', () {
    seed(
      [patient('p1')],
      [alert('warn', patientId: 'p1', severity: RiskLevel.warning)],
    );
    expect(AlertCenter.instance.shouldRing, isFalse,
        reason: 'a warning should not make the phone ring');

    seed([patient('p1')], [alert('crit', patientId: 'p1')]);
    expect(AlertCenter.instance.shouldRing, isTrue);
  });

  test('alerts outside the visible scope are never surfaced', () {
    // Alert references a patient this user cannot see.
    seed([patient('p1')], [alert('a1', patientId: 'someone-else')]);

    expect(AlertCenter.instance.openQueue, isEmpty);
  });

  test('signed-out sessions neither queue nor ring', () {
    seed([patient('p1')], [alert('a1', patientId: 'p1')]);
    expect(AlertCenter.instance.dueNow, hasLength(1));

    AuthState.instance.signOut();

    expect(AlertCenter.instance.openQueue, isEmpty);
    expect(AlertCenter.instance.shouldRing, isFalse,
        reason: 'ringing is gated on an active session');
  });

  test('reset clears escalation history so the next user starts clean', () {
    seed([patient('p1')], [alert('a1', patientId: 'p1')]);
    AlertCenter.instance.markSurfaced(['alert:a1']);
    expect(AlertCenter.instance.surfaceCountFor('alert:a1'), 1);

    AlertCenter.instance.reset();

    expect(AlertCenter.instance.surfaceCountFor('alert:a1'), 0);
    expect(AlertCenter.instance.dueNow, hasLength(1));
  });
}

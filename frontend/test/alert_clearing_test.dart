import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/shared/alerts/alert_center.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/services/sos_ring_service.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/state/staff_state.dart';

/// Working an alert has to clear it everywhere it is counted.
///
/// Three surfaces read the same state and are easy to drift apart: the urgent
/// queue that drives the banners, the notification inbox and its unread
/// badge, and the SOS list. If any one of them keeps a closed emergency, the
/// app tells a responder that people are still waiting when they are not.
void main() {
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

  StaffAlert alert(String id) => StaffAlert(
    id: id,
    patientId: 'p1',
    patientName: 'Patient p1',
    vital: VitalKey.bloodPressure,
    value: '190/120',
    severity: RiskLevel.critical,
    createdAt: DateTime.now(),
  );

  StaffPatientSos sos(String id, {String status = 'active'}) =>
      StaffPatientSos(
        id: id,
        patientId: 'p1',
        patientName: 'Patient p1',
        kind: 'medical',
        status: status,
        triggeredAt: DateTime.now(),
      );

  void seed({List<StaffAlert> alerts = const [], List<StaffPatientSos> sosEvents = const []}) {
    StaffState.instance.seedFromApi(
      patients: [patient('p1')],
      alerts: alerts,
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      sosEvents: sosEvents,
    );
  }

  int staffUnread() => NotificationState.instance.items
      .where((n) => n.id.startsWith('staff_') && !n.read && !n.resolved)
      .length;

  bool hasNotification(String id) =>
      NotificationState.instance.items.any((n) => n.id == id);

  setUp(() {
    AlertCenter.instance.reset();
    AuthState.instance.signIn(
      AppUser(
        id: 'u1',
        uniqueId: 'MCR-000001',
        firstName: 'Test',
        lastName: 'Admin',
        email: 'admin@mcare.health',
        role: UserRole.admin,
      ),
    );
    ApiClient.instance.setTransportForTesting(
      MockClient(
        (_) async => http.Response(
          '{"success":true}',
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    AlertCenter.instance.reset();
    SosRingService.instance.stop();
    StaffState.instance.clear();
    NotificationState.instance.seed(const []);
  });

  test('a resolved SOS leaves the queue, the inbox and the badge', () async {
    seed(sosEvents: [sos('s1')]);

    expect(AlertCenter.instance.openQueue, hasLength(1));
    expect(hasNotification('staff_sos_s1'), isTrue);
    expect(staffUnread(), 1);

    final ok = await StaffState.instance.adminResolveSos(
      's1',
      status: 'resolved',
    );

    expect(ok, isTrue);
    expect(
      StaffState.instance.patientSos.where((e) => e.isActive),
      isEmpty,
      reason: 'the SOS list must not still show a closed emergency',
    );
    expect(AlertCenter.instance.openQueue, isEmpty);
    expect(hasNotification('staff_sos_s1'), isFalse);
    expect(staffUnread(), 0, reason: 'the badge has to come down too');
  });

  test('a false alarm clears exactly like a resolution', () async {
    seed(sosEvents: [sos('s1')]);

    await StaffState.instance.adminResolveSos('s1', status: 'falseAlarm');

    expect(AlertCenter.instance.openQueue, isEmpty);
    expect(hasNotification('staff_sos_s1'), isFalse);
    expect(staffUnread(), 0);
  });

  test('acknowledging an SOS keeps it listed but stops it interrupting', () async {
    seed(sosEvents: [sos('s1')]);

    await StaffState.instance.adminResolveSos('s1', status: 'acknowledged');

    expect(
      StaffState.instance.patientSos.single.status,
      'acknowledged',
      reason: 'ownership is not resolution — it stays on the SOS list',
    );
    expect(AlertCenter.instance.openQueue, hasLength(1));
    expect(
      AlertCenter.instance.popQueue,
      isEmpty,
      reason: 'an owned emergency must stop interrupting the responder',
    );
  });

  test('acknowledging a vital alert clears its unread badge', () async {
    seed(alerts: [alert('a1')]);

    expect(staffUnread(), 1);

    final ok = await StaffState.instance.acknowledgeAlert('a1');

    expect(ok, isTrue);
    expect(
      hasNotification('staff_alert_a1'),
      isTrue,
      reason: 'an owned alert stays on the board until it is resolved',
    );
    expect(staffUnread(), 0, reason: 'but it is no longer demanding attention');
    expect(AlertCenter.instance.popQueue, isEmpty);
  });

  test('resolving a vital alert removes it from the inbox entirely', () async {
    seed(alerts: [alert('a1')]);

    final ok = await StaffState.instance.resolveAlert(
      'a1',
      actionTaken: 'Contacted patient',
      note: 'Reading repeated and normal.',
    );

    expect(ok, isTrue);
    expect(AlertCenter.instance.openQueue, isEmpty);
    expect(hasNotification('staff_alert_a1'), isFalse);
    expect(staffUnread(), 0);
  });

  test('a failed resolve puts the alert back rather than swallowing it', () async {
    ApiClient.instance.setTransportForTesting(
      MockClient(
        (_) async => http.Response(
          '{"success":false,"message":"Nope."}',
          500,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
    seed(sosEvents: [sos('s1')]);

    final ok = await StaffState.instance.adminResolveSos(
      's1',
      status: 'resolved',
    );

    expect(ok, isFalse);
    expect(
      AlertCenter.instance.openQueue,
      hasLength(1),
      reason: 'an emergency that did not actually close must come back',
    );
    expect(hasNotification('staff_sos_s1'), isTrue);
  });
}

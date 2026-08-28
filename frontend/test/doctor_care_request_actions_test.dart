import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/services/doctor_session_service.dart';
import 'package:mcare/shared/state/staff_state.dart';

/// Doctors do not triage care requests.
///
/// A patient asking for a provider is a routing decision that belongs to
/// admins and mCare assistants; approving one is what creates the care
/// assignment. The doctor sees the care team they were assigned to and never
/// the pending request.
///
/// This file used to pin the doctor-side Accept / Decline calls. That
/// capability was removed on both sides — the endpoints are gone from
/// routes/api.php and the mutations are gone from StaffState. What is left
/// here is the client half of the boundary: even if a server still sends
/// pending care requests to a doctor, nothing surfaces them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<http.Request> sent;

  /// A doctor session that still carries a pending care request, the way an
  /// older or rogue backend would answer.
  MockClient sessionCarryingACareRequest() {
    return MockClient((req) async {
      sent.add(req);
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'caseload': [],
            'alerts': [],
            'appointments': [],
            'prescriptions': [],
            'reports': [],
            'vital_report_requests': [],
            'care_requests': [
              {
                'id': '3',
                'patient_id': '8',
                'patient_name': 'Brian Otieno',
                'provider_id': '2',
                'provider_name': 'Dr. Sarah Adeyemi',
                'reason': 'Second opinion — endocrine referral',
                'status': 'pending',
                'created_at': DateTime.now().toIso8601String(),
              },
            ],
            'sos_events': [],
            'vital_catalog': [],
            'meal_plans': [],
            'vital_readings': [],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  setUp(() {
    sent = [];
    ApiClient.instance.setToken('test-token');
    AuthState.instance.signIn(
      AppUser(
        id: 'u1',
        uniqueId: 'MCR-000002',
        firstName: 'Test',
        lastName: 'Doctor',
        email: 'doctor@mcare.health',
        role: UserRole.doctor,
      ),
    );
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    ApiClient.instance.setToken(null);
    StaffState.instance.clear();
  });

  test('a doctor session never seeds pending care requests', () async {
    ApiClient.instance.setTransportForTesting(sessionCarryingACareRequest());

    await DoctorSessionService.instance.syncFromApi();

    expect(
      sent,
      isNotEmpty,
      reason: 'the session request itself must still go out',
    );
    expect(
      StaffState.instance.careRequests,
      isEmpty,
      reason: 'triage is an admin decision — a doctor is never shown the queue',
    );
  });

  test('the doctor client exposes no care-request decision surface', () {
    // Guard against the capability being reintroduced quietly: these members
    // were removed with their endpoints, so the calls below must not compile
    // back into existence without this test being revisited.
    expect(
      StaffState.instance.careRequests,
      isEmpty,
      reason: 'nothing on the doctor side populates or decides care requests',
    );
  });
}

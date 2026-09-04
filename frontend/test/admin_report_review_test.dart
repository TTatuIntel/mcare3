import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mcare/admin/reports/admin_reports_view.dart';
import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/patient_report_request.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// Where a signed report goes, and what an admin can do with it.
///
/// A doctor signing used to end the workflow in mid-air: the notification the
/// backend wrote pointed at `/admin/reports`, which did not exist, and the
/// report itself was reachable only by remembering whose it was and reopening
/// that patient's row. `AdminApi.listReportRequests` was written and never
/// called from anywhere. So a signed report waited on somebody happening to go
/// looking for it.
///
/// These tests pin the queue that fixes it — that a signed report lands in the
/// admin's own tab rather than the general pile — and the model contract the
/// three decisions hang off.
void main() {
  /// Every report request the stubbed API hands back.
  late List<Map<String, dynamic>> serverRows;

  setUp(() {
    serverRows = [];
    // The backend flag is compile-time and defaults to on, so the screen takes
    // the real API path. Stubbing the transport keeps that path under test
    // rather than falling through to the offline branch, which is not the code
    // admins run.
    ApiClient.instance.setTransportForTesting(
      MockClient((req) async {
        if (req.url.path.endsWith('/admin/report-requests')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'report_requests': serverRows},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"success":true,"data":{}}',
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    AuthState.instance.signIn(
      const AppUser(
        id: 'a1',
        uniqueId: 'AD-001',
        firstName: 'Ada',
        lastName: 'Admin',
        email: 'ada@example.com',
        role: UserRole.admin,
      ),
    );
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
  });

  Future<void> pumpQueue(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const AdminReportsScreen(
          currentRoute: '/admin/reports',
          destinations: [],
          profileRoute: '/admin/profile',
          notificationsRoute: '/admin/notifications',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a signed report lands in the admin’s own queue', (tester) async {
    serverRows = [
      _row(
        id: '1',
        patient: 'Kib Lug',
        status: 'signed',
        signedAt: '2026-08-30T10:00:00Z',
        awaitingIssueDecision: true,
      ),
    ];

    await pumpQueue(tester);

    // Opens on the tab that has something in it, not on a general list the
    // admin then has to filter down themselves.
    expect(find.text('Kib Lug'), findsOneWidget);
    expect(find.text('Signed — ready to issue'), findsOneWidget);
  });

  testWidgets('a report still waiting on a doctor is not in that queue', (
    tester,
  ) async {
    serverRows = [
      _row(
        id: '2',
        patient: 'Unsigned Patient',
        status: 'pending_signature',
        blockedOn: 'doctor_signature',
      ),
    ];

    await pumpQueue(tester);

    // Nothing for the admin to decide yet, so the "Awaiting you" tab is empty
    // and says so rather than showing a report they cannot act on.
    expect(find.text('Nothing waiting on you'), findsOneWidget);
    expect(find.text('Unsigned Patient'), findsNothing);

    await tester.tap(find.text('In progress'));
    await tester.pumpAndSettle();
    expect(find.text('Unsigned Patient'), findsOneWidget);
  });

  testWidgets('an issued report leaves the decision queue', (tester) async {
    serverRows = [
      _row(
        id: '3',
        patient: 'Done Patient',
        status: 'issued',
        signedAt: '2026-08-30T10:00:00Z',
        issuedAt: '2026-08-30T11:00:00Z',
      ),
    ];

    await pumpQueue(tester);

    expect(find.text('Nothing waiting on you'), findsOneWidget);

    await tester.tap(find.text('Issued'));
    await tester.pumpAndSettle();
    expect(find.text('Done Patient'), findsOneWidget);
  });

  /// A report that has been round the houses should say so in the list. Three
  /// returns is a conversation that has stopped working, and that is only
  /// visible by comparing rows.
  testWidgets('a returned report shows how many trips it has taken', (
    tester,
  ) async {
    serverRows = [
      _row(
        id: '4',
        patient: 'Kib Lug',
        status: 'signed',
        signedAt: '2026-08-30T10:00:00Z',
        awaitingIssueDecision: true,
        returnCount: 3,
      ),
    ];

    await pumpQueue(tester);

    expect(find.text('Returned 3×'), findsOneWidget);
  });

  group('the model contract the three decisions hang off', () {
    test('a returned report reads as awaiting rework, not as new', () {
      final r = PatientReportRequestItem.fromJson(
        _row(
          id: '5',
          patient: 'Kib Lug',
          status: 'pending_signature',
          blockedOn: 'doctor_signature',
          awaitingRework: true,
          returnedAt: '2026-08-30T12:00:00Z',
          returnNote: 'Recipient address is wrong.',
          returnedByName: 'Ada Admin',
          returnCount: 1,
        ),
      );

      expect(r.awaitingRework, isTrue);
      expect(r.awaitingIssueDecision, isFalse);
      expect(r.returnNote, 'Recipient address is wrong.');
      expect(r.returnedByName, 'Ada Admin');
      expect(r.returnCount, 1);
    });

    /// The flags are server-set on purpose: the queue and the badge read the
    /// same field, so they cannot drift apart the way two client-side
    /// re-derivations of "is this waiting on me" would.
    test('a signed report reads as awaiting the admin', () {
      final r = PatientReportRequestItem.fromJson(
        _row(
          id: '6',
          patient: 'Kib Lug',
          status: 'signed',
          signedAt: '2026-08-30T10:00:00Z',
          awaitingIssueDecision: true,
        ),
      );

      expect(r.awaitingIssueDecision, isTrue);
      expect(r.awaitingRework, isFalse);
      expect(r.isIssued, isFalse);
    });

    test('missing return fields default to never returned', () {
      final r = PatientReportRequestItem.fromJson(
        _row(id: '7', patient: 'Kib Lug', status: 'draft'),
      );

      expect(r.returnCount, 0);
      expect(r.returnedAt, isNull);
      expect(r.awaitingRework, isFalse);
      expect(r.awaitingIssueDecision, isFalse);
    });
  });
}

Map<String, dynamic> _row({
  required String id,
  required String patient,
  required String status,
  String? blockedOn,
  String? signedAt,
  String? issuedAt,
  bool awaitingIssueDecision = false,
  bool awaitingRework = false,
  String? returnedAt,
  String? returnedByName,
  String? returnNote,
  int returnCount = 0,
}) {
  return {
    'id': id,
    'patient_id': 'p$id',
    'patient_name': patient,
    'title': 'Discharge paperwork',
    'purpose': 'Insurance claim',
    'status': status,
    'status_label': switch (status) {
      'signed' => 'Signed — ready to issue',
      'pending_signature' => 'Awaiting doctor signature',
      'issued' => 'Issued',
      _ => 'Draft',
    },
    'blocked_on': blockedOn,
    'sections': ['identity'],
    'section_labels': ['Identity'],
    'consent_required': true,
    'signature_required': true,
    'consented_at': '2026-08-29T09:00:00Z',
    'signed_at': signedAt,
    'signature_name': signedAt == null ? null : 'Dr. Signer',
    'issued_at': issuedAt,
    'awaiting_issue_decision': awaitingIssueDecision,
    'awaiting_rework': awaitingRework,
    'returned_at': returnedAt,
    'returned_by_name': returnedByName,
    'return_note': returnNote,
    'return_count': returnCount,
    'created_at': '2026-08-28T09:00:00Z',
  };
}

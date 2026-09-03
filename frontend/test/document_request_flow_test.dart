import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mcare/core/api/api_client.dart';
import 'package:mcare/patients/documents/documents_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/document.dart';
import 'package:mcare/shared/models/document_request.dart';
import 'package:mcare/shared/models/request_activity_event.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/state/document_requests_state.dart';
import 'package:mcare/shared/state/documents_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The documents screen holds two different things and must not blur them:
/// what is filed, which the patient can open, and what has been asked for,
/// which they cannot. What these tests hold to is that an outstanding request
/// is visible and says who has it, that a claim reads differently from
/// silence, that a decline shows its reason, and that searching and filtering
/// narrow the record without ever hiding an open request.
void main() {
  final now = DateTime.now();

  DocumentRequest request({
    required String id,
    required String title,
    DocumentRequestStatus status = DocumentRequestStatus.pending,
    DocumentCategory category = DocumentCategory.referral,
    String? claimedByName,
    String? declineReason,
    DateTime? neededBy,
    bool overdue = false,
    List<RequestActivityEvent> events = const [],
  }) => DocumentRequest(
    id: id,
    title: title,
    category: category,
    target: DocumentRequestTarget.team,
    status: status,
    createdAt: now.subtract(const Duration(days: 1)),
    claimedByName: claimedByName,
    declineReason: declineReason,
    neededBy: neededBy,
    overdue: overdue,
    events: events,
  );

  MedicalDocument document({
    required String id,
    required String title,
    DocumentCategory category = DocumentCategory.labResult,
    DocumentSource source = DocumentSource.patient,
  }) => MedicalDocument(
    id: id,
    title: title,
    category: category,
    fileType: DocumentFileType.pdf,
    sizeBytes: 2048,
    uploadedAt: now.subtract(const Duration(days: 2)),
    uploadedBy: 'You',
    source: source,
  );

  setUp(() {
    // The screen refreshes both lists on open. Answering everything with an
    // empty payload would wipe the seeds under test, so the stub returns what
    // each store already holds — the same shape the server sends.
    ApiClient.instance.setTransportForTesting(
      MockClient((req) async {
        if (req.url.path.endsWith('/patient/document-requests')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'requests': _requestsAsApi()},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'documents': _documentsAsApi()},
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    AuthState.instance.signIn(
      const AppUser(
        id: 'p1',
        uniqueId: 'PT-001',
        firstName: 'Amara',
        lastName: 'Doe',
        email: 'amara@example.com',
        role: UserRole.patient,
      ),
    );
  });

  tearDown(() {
    ApiClient.instance.setTransportForTesting(null);
    DocumentsState.instance.seed(const []);
    DocumentRequestsState.instance.seed(const []);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const DocumentsView()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an unclaimed request says nobody has it yet', (tester) async {
    DocumentsState.instance.seed([document(id: 'd1', title: 'Lipid panel')]);
    DocumentRequestsState.instance.seed([
      request(id: 'r1', title: 'Referral letter for physiotherapy'),
    ]);

    await pump(tester);

    expect(find.text('Waiting on your care team'), findsOneWidget);
    expect(find.text('Referral letter for physiotherapy'), findsOneWidget);
    expect(find.textContaining('Waiting on'), findsWidgets);
  });

  testWidgets('a claimed request names who is preparing it', (tester) async {
    DocumentRequestsState.instance.seed([
      request(
        id: 'r1',
        title: 'Referral letter',
        status: DocumentRequestStatus.inProgress,
        claimedByName: 'Dr. Kojo Mensah',
      ),
    ]);

    await pump(tester);

    // The whole point of the claim: silence and work in progress must not
    // read the same.
    expect(
      find.text('Dr. Kojo Mensah is preparing this'),
      findsOneWidget,
    );
    expect(find.text('Being prepared'), findsWidgets);
  });

  testWidgets('a decline is shown with its reason, not just a status', (
    tester,
  ) async {
    DocumentRequestsState.instance.seed([
      request(
        id: 'r1',
        title: 'Old discharge summary',
        status: DocumentRequestStatus.declined,
        declineReason: 'That record is held by your previous practice.',
      ),
    ]);

    await pump(tester);

    // Answered requests are folded away, so the reason lives one tap in.
    await tester.tap(find.textContaining('Show 1 answered request'));
    await tester.pumpAndSettle();

    expect(
      find.text('That record is held by your previous practice.'),
      findsOneWidget,
    );
  });

  testWidgets('an overdue request is called out rather than left to notice', (
    tester,
  ) async {
    DocumentRequestsState.instance.seed([
      request(
        id: 'r1',
        title: 'Fit note',
        neededBy: now.subtract(const Duration(days: 3)),
        overdue: true,
      ),
    ]);

    await pump(tester);

    expect(find.text('Overdue'), findsWidgets);
    expect(
      find.textContaining('past the date you needed it'),
      findsOneWidget,
    );
  });

  testWidgets('an issued vital report is filed under its own category', (
    tester,
  ) async {
    DocumentsState.instance.seed([
      document(
        id: 'd1',
        title: 'Vital report — 1 Aug 2026 to 30 Aug 2026',
        category: DocumentCategory.vitalReport,
        source: DocumentSource.report,
      ),
      document(id: 'd2', title: 'Lipid panel'),
    ]);

    await pump(tester);

    expect(find.text('Vital report'), findsWidgets);
    // Issued reports are not the patient's to delete, and the row says so.
    expect(find.text('Issued report'), findsOneWidget);
  });

  testWidgets('search narrows the record but never hides an open request', (
    tester,
  ) async {
    DocumentsState.instance.seed([
      document(id: 'd1', title: 'Lipid panel'),
      document(id: 'd2', title: 'Chest X-ray', category: DocumentCategory.imaging),
    ]);
    DocumentRequestsState.instance.seed([
      request(id: 'r1', title: 'Referral letter for physiotherapy'),
    ]);

    await pump(tester);
    expect(find.text('Chest X-ray'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'lipid');
    await tester.pumpAndSettle();

    expect(find.text('Lipid panel'), findsOneWidget);
    expect(find.text('Chest X-ray'), findsNothing);
    // A search over what is filed must not swallow what is still outstanding —
    // that is the one thing the patient came here to check on.
    expect(find.text('Referral letter for physiotherapy'), findsOneWidget);
  });

  testWidgets('an empty record offers both directions, not just upload', (
    tester,
  ) async {
    DocumentsState.instance.seed(const []);
    DocumentRequestsState.instance.seed(const []);

    await pump(tester);

    expect(find.text('Nothing filed yet'), findsOneWidget);
    expect(find.widgetWithText(InkWell, 'Upload'), findsWidgets);
    expect(find.text('Request'), findsWidgets);
  });
}

List<Map<String, dynamic>> _requestsAsApi() => DocumentRequestsState.instance.all
    .map(
      (r) => {
        'id': r.id,
        'title': r.title,
        'category': r.category.name,
        'note': r.note,
        'target': r.target.name,
        'target_doctor_id': r.targetDoctorId,
        'target_doctor_name': r.targetDoctorName,
        'needed_by': r.neededBy?.toIso8601String(),
        'overdue': r.overdue,
        'status': r.status == DocumentRequestStatus.inProgress
            ? 'in_progress'
            : r.status.name,
        'created_at': r.createdAt.toIso8601String(),
        'claimed_by_name': r.claimedByName,
        'claimed_at': r.claimedAt?.toIso8601String(),
        'waiting_on': r.waitingOn,
        'resolved_at': r.resolvedAt?.toIso8601String(),
        'resolved_by_name': r.resolvedByName,
        'resolution_note': r.resolutionNote,
        'decline_reason': r.declineReason,
        'document_id': r.documentId,
        'events': const [],
      },
    )
    .toList();

List<Map<String, dynamic>> _documentsAsApi() => DocumentsState.instance.all
    .map(
      (d) => {
        'id': d.id,
        'title': d.title,
        'category': d.category.name,
        'file_type': d.fileType.name,
        'size_bytes': d.sizeBytes,
        'uploaded_at': d.uploadedAt.toIso8601String(),
        'uploaded_by': d.uploadedBy,
        'description': d.description,
        'shared_with_doctor_id': d.sharedWithDoctorId,
        'has_file': d.hasFile,
        'source': d.source.name,
        'issued_report_id': d.issuedReportId,
        'removal_requested': d.removalRequested,
        'can_request_removal': d.canRequestRemoval,
      },
    )
    .toList();

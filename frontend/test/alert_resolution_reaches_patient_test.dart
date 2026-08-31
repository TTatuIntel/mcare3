import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/core/api/patient_domain_mapper.dart';
import 'package:mcare/patients/dashboard/patient_dashboard_view.dart';
import 'package:mcare/shared/auth/auth_state.dart';
import 'package:mcare/shared/models/announcement.dart';
import 'package:mcare/shared/models/app_user.dart';
import 'package:mcare/shared/models/notification_item.dart';
import 'package:mcare/shared/models/user_role.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/announcements_state.dart';
import 'package:mcare/shared/state/appointments_state.dart';
import 'package:mcare/shared/state/meal_plans_state.dart';
import 'package:mcare/shared/state/medications_state.dart';
import 'package:mcare/shared/state/messages_state.dart';
import 'package:mcare/shared/state/notification_state.dart';
import 'package:mcare/shared/state/sos_state.dart';
import 'package:mcare/shared/state/support_state.dart';
import 'package:mcare/shared/state/vital_report_state.dart';
import 'package:mcare/shared/state/vitals_state.dart';
import 'package:mcare/shared/theme/app_theme.dart';

/// The last leg of a resolution: from the clinician who closed it to the
/// patient's own screen.
///
/// A doctor resolving a critical reading used to change nothing the patient
/// could see. The reason went into a staff-only field, the closure notice
/// arrived typed as a generic system row, it never linked back to the vital it
/// was about, and the red card on the home screen kept shouting the same
/// number — because that card read the reading, not the conversation about it.
/// These hold the whole leg: the notice arrives as a resolution, it points at
/// the right vital, and the home screen stops sounding an alarm once the care
/// team has answered.
void main() {
  group('the closure notice arrives as what it is', () {
    test('a vital alert is not filed as a generic system message', () {
      expect(
        PatientDomainMapper.notificationKindFromApi('vital_critical'),
        NotificationKind.vitalAlert,
      );
      expect(
        PatientDomainMapper.notificationKindFromApi('vital_warning'),
        NotificationKind.vitalAlert,
      );
    });

    test('a resolution reads as an answer, not a new emergency', () {
      expect(
        PatientDomainMapper.notificationKindFromApi('alert_resolved'),
        NotificationKind.resolution,
      );
      expect(
        PatientDomainMapper.notificationKindFromApi('sos_resolved'),
        NotificationKind.resolution,
      );
    });

    test('an unknown kind still lands somewhere sensible', () {
      expect(
        PatientDomainMapper.notificationKindFromApi('something_new'),
        NotificationKind.system,
      );
    });

    test('the notice links back to the vital the API named', () {
      final notice = PatientDomainMapper.notificationFromApi({
        'id': 'n1',
        'kind': 'alert_resolved',
        'title': 'Heart rate alert resolved',
        'body': 'Dr. Mensah reviewed your heart rate alert · Patient '
            'contacted. Resting and stable.',
        'created_at': DateTime.now().toIso8601String(),
        'action_route': '/patient/vitals',
        'action_arguments': {'vital_key': 'heartRate', 'alert_id': '7'},
      });

      expect(notice.kind, NotificationKind.resolution);
      expect(notice.linkedVital, VitalKey.heartRate);
    });

    test('the state finds the notice for a vital', () {
      final now = DateTime.now();
      NotificationState.instance.seed([
        AppNotification(
          id: 'old',
          kind: NotificationKind.resolution,
          title: 'Heart rate alert resolved',
          body: 'Earlier answer.',
          createdAt: now.subtract(const Duration(days: 2)),
          actionArguments: VitalKey.heartRate,
        ),
        AppNotification(
          id: 'new',
          kind: NotificationKind.resolution,
          title: 'Heart rate alert resolved',
          body: 'Latest answer.',
          createdAt: now,
          actionArguments: VitalKey.heartRate,
        ),
        AppNotification(
          id: 'other',
          kind: NotificationKind.resolution,
          title: 'Blood oxygen alert resolved',
          body: 'A different vital.',
          createdAt: now,
          actionArguments: VitalKey.bloodOxygen,
        ),
      ]);

      expect(
        NotificationState.instance.resolutionNoticeFor(VitalKey.heartRate)?.id,
        'new',
      );
      expect(
        NotificationState.instance.resolutionNoticeFor(VitalKey.weight),
        isNull,
      );

      NotificationState.instance.seed([]);
    });
  });

  group('the home screen after the care team answers', () {
    setUp(() {
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

      VitalsState.instance.seedEnabledCatalog(VitalKey.values);
      VitalsState.instance.seedAssigned([VitalKey.heartRate]);
      VitalsState.instance.seedTracked([VitalKey.heartRate]);
      VitalsState.instance.seed([
        VitalReading(
          id: 'r1',
          vital: VitalKey.heartRate,
          value: 39,
          recordedAt: DateTime.now().subtract(const Duration(minutes: 20)),
          risk: RiskLevel.critical,
        ),
      ]);

      AppointmentsState.instance.seed([]);
      MedicationsState.instance.seed(meds: const [], doses: const []);
      MessagesState.instance.seed(conversations: const [], threads: const {});
      SupportState.instance.seed([]);
      VitalReportState.instance.seed([]);
      SosState.instance.seed(contacts: const [], history: const []);
      AnnouncementsState.instance.seed(const <AppAnnouncement>[]);
      MealPlansState.instance.seed(const []);
      NotificationState.instance.seed([]);
    });

    tearDown(() {
      VitalsState.instance.seed([]);
      NotificationState.instance.seed([]);
    });

    testWidgets('an open alert still leads with the alarm', (tester) async {
      NotificationState.instance.seed([
        AppNotification(
          id: 'a1',
          kind: NotificationKind.vitalAlert,
          title: 'Heart rate is critical',
          body: '39 bpm recorded at 2:45 PM',
          createdAt: DateTime.now(),
          actionArguments: VitalKey.heartRate,
        ),
      ]);

      await _pumpDashboard(tester);

      expect(_showing(tester, 'Care alert'), isTrue);
      expect(_showing(tester, 'Reviewed by your care team'), isFalse);

      await _dispose(tester);
    });

    testWidgets('a closed alert shows the answer, not the alarm', (
      tester,
    ) async {
      // The same dangerous reading — but the care team has been through it.
      NotificationState.instance.seed([
        AppNotification(
          id: 'a1',
          kind: NotificationKind.vitalAlert,
          title: 'Heart rate is critical',
          body: '39 bpm recorded at 2:45 PM',
          createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
          resolved: true,
          resolvedAt: DateTime.now(),
          read: true,
          actionArguments: VitalKey.heartRate,
        ),
        AppNotification(
          id: 'r1',
          kind: NotificationKind.resolution,
          title: 'Heart rate alert resolved',
          body: 'Dr. Mensah reviewed your heart rate alert · Patient '
              'contacted. Resting and stable, recheck at 6pm.',
          createdAt: DateTime.now(),
          actionArguments: VitalKey.heartRate,
        ),
      ]);

      await _pumpDashboard(tester);

      expect(
        _showing(tester, 'Reviewed by your care team'),
        isTrue,
        reason: 'the patient has been told, so the card must stop alarming',
      );
      expect(_showing(tester, 'Care alert'), isFalse);
      expect(
        _showing(
          tester,
          'Dr. Mensah reviewed your heart rate alert · Patient contacted. '
          'Resting and stable, recheck at 6pm.',
        ),
        isTrue,
        reason: 'the reason the clinician gave is the point of the card',
      );

      await _dispose(tester);
    });
  });
}

Future<void> _pumpDashboard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: const PatientDashboardView()),
  );
  // Let the staggered entry animations run out. Never pumpAndSettle: the live
  // badge pulses forever by design.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

bool _showing(WidgetTester tester, String text) {
  final finder = find.ancestor(
    of: find.text(text),
    matching: find.byType(AnimatedOpacity),
  );
  if (finder.evaluate().isEmpty) return false;
  return tester.widget<AnimatedOpacity>(finder.first).opacity == 1;
}

Future<void> _dispose(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mcare/core/api/patient_chart_api.dart';
import 'package:mcare/doctors/patients/doctor_patient_section.dart';
import 'package:mcare/doctors/widgets/doctor_patient_quick_links.dart';
import 'package:mcare/shared/models/user_dossier.dart';
import 'package:mcare/shared/theme/app_theme.dart';
import 'package:mcare/shared/widgets/dossier/dossier_blocks.dart';
import 'package:mcare/shared/widgets/patient_chart/patient_chart_body.dart';
import 'package:mcare/shared/widgets/patient_page_blocks.dart';
import 'package:mcare/shared/widgets/period_filter_bar.dart';
import 'package:mcare/shared/widgets/staff_patient_profile_sheet.dart';

void main() {
  testWidgets('doctor patient tools stay readable on a narrow phone', (
    tester,
  ) async {
    await _setViewport(tester, const Size(320, 720));

    await tester.pumpWidget(
      _TestApp(
        child: DoctorPatientQuickLinks(
          selected: DoctorPatientSection.overview,
          badges: const <DoctorPatientSection, int>{},
          onSelected: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('Appointments'), findsOneWidget);
    expect(find.text('Prescriptions'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    final overviewTop = tester.getTopLeft(find.text('Overview')).dy;
    final moreTop = tester.getTopLeft(find.text('More')).dy;
    expect(moreTop, greaterThan(overviewTop));

    for (final element in find.byType(PatientQuickAction).evaluate()) {
      final size = tester.getSize(find.byWidget(element.widget));
      expect(size.height, greaterThanOrEqualTo(58));
      expect(size.width, greaterThanOrEqualTo(80));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin dossier exposes every metric and uses two-row sections', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 900));
    var selected = -1;

    await tester.pumpWidget(
      _TestApp(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const DossierStatStrip(stats: _patientStats),
              const SizedBox(height: 16),
              DossierSegments(
                segments: const ['Overview', 'Clinical', 'Account', 'Activity'],
                selected: 0,
                onSelect: (value) => selected = value,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    for (final stat in _patientStats) {
      expect(find.text(stat.label), findsOneWidget);
      expect(find.text(stat.value), findsOneWidget);
    }
    expect(
      tester.getSize(find.byType(DossierStatStrip)).height,
      greaterThanOrEqualTo(250),
    );
    expect(
      tester.getSize(find.byType(DossierSegments)).height,
      greaterThanOrEqualTo(100),
    );

    await tester.tap(find.text('Clinical'));
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff patient entry opens the clinical chart', (tester) async {
    await _setViewport(tester, const Size(360, 900));

    await tester.pumpWidget(
      _TestApp(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => StaffPatientProfileSheet.show(
              context,
              patientId: '17',
              patientName: 'Amara Okonkwo',
            ),
            child: const Text('Open patient'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open patient'));
    await tester.pump();

    expect(find.byType(PatientChartBody), findsOneWidget);
    expect(find.text('Patient chart'), findsOneWidget);
    // The chart opens on its default window, and says which one it is.
    expect(find.byType(PeriodFilterBar), findsOneWidget);
    expect(find.text(ChartPeriod.month.label), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _patientStats = <DossierStat>[
  DossierStat(
    key: 'engagement',
    label: 'Engagement',
    value: '82%',
    tone: 'good',
  ),
  DossierStat(key: 'adherence', label: 'Adherence', value: '75%', tone: 'good'),
  DossierStat(
    key: 'readings',
    label: 'Readings 30d',
    value: '14',
    tone: 'good',
  ),
  DossierStat(key: 'medications', label: 'Active meds', value: '2'),
  DossierStat(key: 'alerts', label: 'Unread alerts', value: '1', tone: 'bad'),
  DossierStat(key: 'care_team', label: 'Care team', value: '3', tone: 'good'),
];

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

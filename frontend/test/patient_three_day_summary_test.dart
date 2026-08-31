import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcare/shared/models/meal_plan.dart';
import 'package:mcare/shared/models/vital.dart';
import 'package:mcare/shared/state/staff_state.dart';
import 'package:mcare/shared/widgets/patient_three_day_summary.dart';

/// The summary is a clinical-context card in staff alert popups. It must show
/// only what the record actually contains: a tile per section with real data,
/// nothing at all when there is none. A grid of "no data" placeholders costs a
/// clinician a read during an alert and tells them nothing.
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

  StaffPatientVitalReading reading(
    String patientId, {
    RiskLevel risk = RiskLevel.critical,
    String? note,
  }) => StaffPatientVitalReading(
    patientId: patientId,
    vital: VitalKey.bloodPressure,
    value: '190/120',
    risk: risk,
    recordedAt: DateTime.now(),
    note: note,
  );

  StaffMealPlan mealPlan(String patientId) => StaffMealPlan(
    id: 'm1',
    patientId: patientId,
    patientName: 'Patient $patientId',
    title: 'Low sodium',
    mealType: MealType.lunch,
    assignedAt: DateTime.now(),
    assignedBy: 'Dr. Test',
  );

  StaffPrescription prescription(String patientId, {String status = 'Active'}) =>
      StaffPrescription(
        id: 'rx1',
        patientId: patientId,
        patientName: 'Patient $patientId',
        drug: 'Amlodipine',
        dosage: '5mg',
        frequency: 'Daily',
        duration: '30 days',
        issuedAt: DateTime.now(),
        status: status,
      );

  void seed({
    List<StaffPatientVitalReading> vitals = const [],
    List<StaffMealPlan> meals = const [],
    List<StaffPrescription> prescriptions = const [],
  }) {
    StaffState.instance.seedFromApi(
      patients: [patient('p1')],
      alerts: const [],
      appointments: const [],
      prescriptions: prescriptions,
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      mealPlans: meals,
      vitalReadings: vitals,
    );
  }

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: PatientThreeDaySummary(patientId: 'p1'),
        ),
      ),
    ),
  );

  tearDown(StaffState.instance.clear);

  testWidgets('renders nothing when the patient has no verified records', (
    tester,
  ) async {
    seed();
    await pump(tester);

    expect(find.text('Patient summary · past 3 days'), findsNothing);
    expect(find.text('Vitals'), findsNothing);
    expect(find.text('Meals'), findsNothing);
    expect(find.text('Medications'), findsNothing);
    expect(find.text('Clinical notes'), findsNothing);
    expect(PatientThreeDaySummary.hasDataFor('p1'), isFalse);
  });

  testWidgets('shows only the sections that have data', (tester) async {
    seed(vitals: [reading('p1')]);
    await pump(tester);

    expect(find.text('Patient summary · past 3 days'), findsOneWidget);
    expect(find.text('Vitals'), findsOneWidget);

    // Sections with nothing on file must not appear as placeholders.
    expect(find.text('Meals'), findsNothing);
    expect(find.text('Medications'), findsNothing);
    expect(find.text('No plan on file'), findsNothing);
    expect(find.text('No active prescription'), findsNothing);
  });

  testWidgets('shows every section once each has a record', (tester) async {
    seed(
      vitals: [reading('p1', note: 'Patient reported dizziness')],
      meals: [mealPlan('p1')],
      prescriptions: [prescription('p1')],
    );
    await pump(tester);

    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('Meals'), findsOneWidget);
    expect(find.text('Medications'), findsOneWidget);
    expect(find.text('Clinical notes'), findsOneWidget);
    expect(find.text('1 plan on file'), findsOneWidget);
    expect(find.text('1 active prescription'), findsOneWidget);
  });

  testWidgets('an inactive prescription is not an active one', (tester) async {
    seed(
      vitals: [reading('p1')],
      prescriptions: [prescription('p1', status: 'Completed')],
    );
    await pump(tester);

    expect(find.text('Vitals'), findsOneWidget);
    expect(find.text('Medications'), findsNothing);
  });

  testWidgets('activity & hydration never renders — nothing feeds it', (
    tester,
  ) async {
    seed(vitals: [reading('p1')], meals: [mealPlan('p1')]);
    await pump(tester);

    expect(find.text('Activity & hydration'), findsNothing);
  });

  testWidgets('vitals older than the 3-day window do not count', (
    tester,
  ) async {
    StaffState.instance.seedFromApi(
      patients: [patient('p1')],
      alerts: const [],
      appointments: const [],
      prescriptions: const [],
      reports: const [],
      vitalRequests: const [],
      careRequests: const [],
      vitalReadings: [
        StaffPatientVitalReading(
          patientId: 'p1',
          vital: VitalKey.bloodPressure,
          value: '190/120',
          risk: RiskLevel.critical,
          recordedAt: DateTime.now().subtract(const Duration(days: 9)),
        ),
      ],
    );
    await pump(tester);

    expect(PatientThreeDaySummary.hasDataFor('p1'), isFalse);
    expect(find.text('Vitals'), findsNothing);
  });
}

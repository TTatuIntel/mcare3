import '../../shared/models/meal_plan.dart';
import '../env/app_env.dart';
import 'api_client.dart';
import 'patient_domain_mapper.dart';

/// The patient's own writes against their nutrition timetable.
///
/// Clinician assignment lives in `DoctorApi`; this covers the two things a
/// patient may do — add or amend a meal they planned themselves, and record
/// whether they followed any meal on their plan, including one a doctor set.
class MealPlansApi {
  MealPlansApi._();
  static final MealPlansApi instance = MealPlansApi._();

  Future<StaffMealPlan?> create(StaffMealPlan draft) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/meal-plans',
      body: PatientDomainMapper.mealPlanToApi(draft),
    );
    return _parse(res);
  }

  Future<StaffMealPlan?> update(StaffMealPlan plan) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.patch(
      '/patient/meal-plans/${plan.id}',
      body: PatientDomainMapper.mealPlanToApi(plan),
    );
    return _parse(res);
  }

  Future<bool> remove(String planId) async {
    if (!AppEnv.backendEnabled) return false;
    await ApiClient.instance.delete('/patient/meal-plans/$planId');
    return true;
  }

  Future<StaffMealPlan?> log({
    required String planId,
    required MealAdherence adherence,
    String? note,
  }) async {
    if (!AppEnv.backendEnabled) return null;
    final res = await ApiClient.instance.post(
      '/patient/meal-plans/$planId/log',
      body: {
        'adherence': adherence.name,
        if (note != null && note.trim().isNotEmpty) 'patient_note': note.trim(),
      },
    );
    return _parse(res);
  }

  StaffMealPlan? _parse(Map<String, dynamic> res) {
    final json = res['data']?['meal_plan'] as Map<String, dynamic>?;
    if (json == null) return null;
    return PatientDomainMapper.mealPlanFromApi(json);
  }
}
